#!/usr/bin/env bash
# ============================================================
# sandbox-mediator.sh — Drop-box mediator for sandboxed execution
#
# This script runs as ROOT (sudoed from the inference user).
# It is the ONLY path by which model-proposed code reaches SANDBOX_DIR.
#
# The write/execute separation works as follows:
#   inference user → writes to STAGING_DIR (its own staging area)
#   inference user → sudo /opt/inference-boot/scripts/sandbox-mediator.sh <file>
#   mediator (root) → validates the staged file
#   mediator (root) → copies to SANDBOX_DIR, sets ownership to sandboxrun
#   mediator (root) → executes via systemd-run as sandboxrun with full confinement
#
# The inference user never writes to SANDBOX_DIR directly.
# The identity that writes to the execution dir is not the identity the model runs as.
# That separation is the control.
#
# Usage: sudo /opt/inference-boot/scripts/sandbox-mediator.sh <filename>
#        (filename must be a basename only — no paths)
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

SANDBOX_USER="sandboxrun"
STAGING_DIR="${STAGING_DIR:-/opt/inference-boot/sandbox-staging}"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[MEDIATOR]${NC} $*"; }
warn()  { echo -e "${YELLOW}[MEDIATOR]${NC} $*"; }
die()   { echo -e "${RED}[MEDIATOR]${NC} $*"; exit 1; }

# ---- Must run as root ----
[[ "$(id -u)" -eq 0 ]] || die "sandbox-mediator.sh must be run as root (via sudo)."

# ---- Accept basename only — no paths, no slashes ----
RAW="${1:?Usage: sudo $0 <filename> (basename only, no paths)}"
[[ "$RAW" == */* ]] && die "Argument must be a filename, not a path. Got: $RAW"

STAGED="${STAGING_DIR}/${RAW}"

# ---- Validate: staged file must exist and be in STAGING_DIR ----
REAL_STAGED=$(realpath -m "$STAGED" 2>/dev/null) || die "Could not resolve staged path."
REAL_STAGING=$(realpath "$STAGING_DIR")
[[ "$REAL_STAGED" == "$REAL_STAGING/"* ]] || die "Path traversal detected: $REAL_STAGED"
[[ -f "$REAL_STAGED" ]] || die "File not found in staging: $REAL_STAGED"

# ---- Validate: no symlinks (prevent staging-dir escape) ----
[[ -L "$REAL_STAGED" ]] && die "Symlinks are not permitted in staging: $RAW"

# ---- Validate: file extension (only known interpreters allowed) ----
case "$RAW" in
  *.py|*.sh) ;;
  *) die "Unsupported file type: $RAW — only .py and .sh are allowed." ;;
esac

# ---- Validate: file size limit (prevent runaway scripts) ----
MAX_BYTES=524288  # 512 KB
FILE_SIZE=$(stat -c%s "$REAL_STAGED")
[[ "$FILE_SIZE" -le "$MAX_BYTES" ]] || \
  die "File too large: ${FILE_SIZE} bytes (max ${MAX_BYTES}). Split into smaller scripts."

# ---- Validate: file must be owned by the inference user (written by them, not injected) ----
OWNER=$(stat -c%U "$REAL_STAGED")
[[ "$OWNER" == "$INFERENCE_USER" ]] || \
  die "Staged file not owned by $INFERENCE_USER (owner: $OWNER) — rejecting."

info "Validated: $RAW (${FILE_SIZE} bytes, owned by $INFERENCE_USER)"

# ---- Copy to sandbox dir as sandboxrun ----
SANDBOX_DEST="${SANDBOX_DIR}/${RAW}"
cp "$REAL_STAGED" "$SANDBOX_DEST"
chown "${SANDBOX_USER}:${SANDBOX_USER}" "$SANDBOX_DEST"
chmod 500 "$SANDBOX_DEST"   # sandboxrun: read+exec only (not writable even by sandboxrun)
info "Copied to sandbox: $SANDBOX_DEST"

# ---- Execute under full systemd confinement ----
case "$RAW" in
  *.py) INTERP="python3" ;;
  *.sh) INTERP="bash"    ;;
esac

info "Executing as $SANDBOX_USER with confinement..."
info "  PrivateNetwork=true | ProtectSystem=strict | ReadWritePaths=$SANDBOX_DIR only"

systemd-run \
  --unit="sandbox-exec-$(date +%s)-$$" \
  --description="Sandboxed execution: $RAW" \
  --property="User=$SANDBOX_USER" \
  --property="Group=$SANDBOX_USER" \
  --property="ProtectSystem=strict" \
  --property="ProtectHome=true" \
  --property="PrivateTmp=true" \
  --property="PrivateDevices=true" \
  --property="ProtectKernelTunables=true" \
  --property="ProtectKernelModules=true" \
  --property="ProtectControlGroups=true" \
  --property="NoNewPrivileges=true" \
  --property="RestrictNamespaces=true" \
  --property="PrivateNetwork=true" \
  --property="ReadWritePaths=$SANDBOX_DIR" \
  --property="MemoryMax=4G" \
  --property="CPUQuota=200%" \
  --property="MemoryDenyWriteExecute=false" \
  --wait \
  --collect \
  -- "$INTERP" "$SANDBOX_DEST"

EXIT=$?

# ---- Clean up from sandbox after execution ----
rm -f "$SANDBOX_DEST"
info "Execution complete (exit: $EXIT). Cleaned up sandbox copy."

# Optionally clean from staging too (inference user can re-stage if needed)
# rm -f "$REAL_STAGED"

exit $EXIT
