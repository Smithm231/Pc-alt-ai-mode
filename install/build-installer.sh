#!/usr/bin/env bash
# ============================================================
# build-installer.sh — pack the whole repo into ONE self-extracting file
#
# Produces a single portable script (default: inference-boot-installer.sh)
# that embeds this entire project as a compressed payload.  Copy that one
# file to a USB stick / live system and it can reproduce the full tree and
# run the install with no git clone and no other files.
#
#   ./install/build-installer.sh                 # -> ./inference-boot-installer.sh
#   ./install/build-installer.sh /tmp/out.sh     # custom output path
#
# Re-run this whenever you change any tracked file so the single file
# stays in sync with the repo.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OUT="${1:-$REPO_DIR/inference-boot-installer.sh}"
MARKER="__INFERENCE_BOOT_PAYLOAD__"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[build]${NC} $*"; }

command -v base64 >/dev/null || { echo "base64 not found"; exit 1; }
command -v tar    >/dev/null || { echo "tar not found"; exit 1; }

cd "$REPO_DIR"

# ---- Collect the file list (tracked files when in git, else everything) ----
# Always exclude the generated single file itself and the VCS dir.
TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_LIST" "$TMP_TAR"' EXIT
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO_DIR" ls-files -z > "$TMP_LIST"
else
  find . -type f -not -path './.git/*' -print0 > "$TMP_LIST"
fi

# Drop the output file and any previously-built installer from the payload.
OUT_BASE="$(basename "$OUT")"
TMP_TAR="$(mktemp --suffix=.tgz)"
tr '\0' '\n' < "$TMP_LIST" \
  | sed 's|^\./||' \
  | grep -v -x "$OUT_BASE" \
  | grep -v -x "inference-boot-installer.sh" \
  | tar czf "$TMP_TAR" -T - --owner=0 --group=0

PAYLOAD_B64="$(base64 < "$TMP_TAR")"
FILE_COUNT="$(tr '\0' '\n' < "$TMP_LIST" | grep -vc -x "$OUT_BASE" || true)"
TAR_SHA="$(sha256sum "$TMP_TAR" | cut -d' ' -f1)"

# ---- Write the self-extracting stub ----
info "Packing $FILE_COUNT files -> $OUT"
cat > "$OUT" <<STUB
#!/usr/bin/env bash
# ====================================================================
#  Inference Boot — Single-File USB Installer  (self-extracting)
# ====================================================================
#  This ONE file contains the entire "Gaming PC alternative inference
#  boot mode" project.  No git clone, no other files needed.
#
#  >>> FOR A LOCAL CLAUDE CODE SESSION ON THE UBUNTU LIVE USB <<<
#  Hand this file to Claude Code and say: "run this installer".
#  Claude should:
#    1. chmod +x this file.
#    2. Run  ./$(basename "$OUT") --extract   to unpack to /tmp/inference-boot.
#    3. Help the user edit  install/install.conf  (TARGET_DRIVE, SATA_SSD_DEVICE,
#       INFERENCE_PASSWORD_HASH or SSH_PUBLIC_KEY, ALLOWED_CIDR, MODEL_REPO).
#       lsblk -d -o NAME,SIZE,MODEL,TRAN   identifies the drives.
#    4. Run  ./$(basename "$OUT") --install /dev/nvmeXnX   to partition,
#       debootstrap and install GRUB onto the second NVMe.  THIS WIPES THAT DRIVE.
#    5. Reboot, pick "InferenceBoot" in the BIOS boot menu; first boot finishes
#       GPU drivers + llama.cpp build + model download automatically.
#
#  Manual use (no Claude):
#    ./$(basename "$OUT") --extract              # unpack only
#    ./$(basename "$OUT") --install /dev/nvme1n1 # unpack + run the installer
#    ./$(basename "$OUT") --help
#
#  Payload: $FILE_COUNT files, sha256(tar)=$TAR_SHA
# ====================================================================
set -euo pipefail

MARKER="$MARKER"
EXTRACT_DIR="\${EXTRACT_DIR:-/tmp/inference-boot}"
SELF="\$0"

c_g='\033[0;32m'; c_y='\033[1;33m'; c_r='\033[0;31m'; c_n='\033[0m'
info() { echo -e "\${c_g}[installer]\${c_n} \$*"; }
warn() { echo -e "\${c_y}[installer]\${c_n} \$*"; }
die()  { echo -e "\${c_r}[installer]\${c_n} \$*" >&2; exit 1; }

usage() {
  cat <<USAGE
Inference Boot single-file installer

Usage:
  \$(basename "\$SELF") --extract [DIR]        Unpack the project (default: /tmp/inference-boot)
  \$(basename "\$SELF") --install /dev/nvmeXnX  Unpack then run the bootstrap installer (WIPES that drive)
  \$(basename "\$SELF") --verify               Check the embedded payload checksum
  \$(basename "\$SELF") --help

Env:
  EXTRACT_DIR   Override the extraction directory.
USAGE
}

payload_start() {
  # Line number of the first base64 line (the last standalone marker line + 1).
  grep -n "^\${MARKER}\$" "\$SELF" | tail -n1 | cut -d: -f1
}

extract() {
  local dir="\${1:-\$EXTRACT_DIR}"
  local start; start="\$(payload_start)"
  [[ -n "\$start" ]] || die "Payload marker not found — file is corrupt."
  mkdir -p "\$dir"
  info "Extracting project to \$dir ..."
  tail -n "+\$((start + 1))" "\$SELF" | base64 -d | tar xzf - -C "\$dir"
  info "Done. Project tree is at: \$dir"
}

verify() {
  local start; start="\$(payload_start)"
  [[ -n "\$start" ]] || die "Payload marker not found."
  local got; got="\$(tail -n "+\$((start + 1))" "\$SELF" | base64 -d | sha256sum | cut -d' ' -f1)"
  if [[ "\$got" == "$TAR_SHA" ]]; then
    info "Payload OK (sha256=\$got)"
  else
    die "Payload checksum mismatch! expected $TAR_SHA got \$got"
  fi
}

main() {
  local cmd="\${1:-}"
  case "\$cmd" in
    --extract|-x) extract "\${2:-}";;
    --verify)     verify;;
    --help|-h|"") usage;;
    --install)
      local drive="\${2:-}"
      [[ -n "\$drive" ]] || die "--install requires a target drive, e.g. --install /dev/nvme1n1"
      [[ "\$(id -u)" -eq 0 ]] || die "--install must run as root (use sudo)."
      extract "\$EXTRACT_DIR"
      info "Launching bootstrap on \$drive ..."
      chmod +x "\$EXTRACT_DIR"/install/*.sh "\$EXTRACT_DIR"/scripts/*.sh 2>/dev/null || true
      exec bash "\$EXTRACT_DIR/install/00-bootstrap.sh" "\$drive"
      ;;
    *) die "Unknown option: \$cmd  (try --help)";;
  esac
}

main "\$@"
exit 0
$MARKER
STUB

# Append the base64 payload (after the marker line written above).
printf '%s\n' "$PAYLOAD_B64" >> "$OUT"
chmod +x "$OUT"

info "Wrote $(du -h "$OUT" | cut -f1) -> $OUT"
info "sha256(payload tar) = $TAR_SHA"
