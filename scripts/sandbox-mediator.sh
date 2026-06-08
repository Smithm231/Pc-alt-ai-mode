#!/usr/bin/env bash
# ============================================================
# sandbox-mediator.sh — Drop-box mediator for sandboxed execution
#
# This script runs as ROOT (sudoed from the inference user).
# It is the ONLY path by which model-proposed code reaches SANDBOX_DIR.
#
# Drop-box flow:
#   inference user → writes to STAGING_DIR (its own area)
#   inference user → sudo sandbox-mediator.sh <filename>
#   mediator (root) → structural checks (basename, extension, path containment, no symlink)
#   mediator (root) → copies staged file to root-owned temp IMMEDIATELY (eliminates TOCTOU)
#   mediator (root) → validates the temp (our copy — not the inference user's original)
#   mediator (root) → moves temp to SANDBOX_DIR as sandboxrun
#   mediator (root) → executes under full systemd confinement as sandboxrun
#
# Security model — the confinement IS the boundary; the mediator is a provenance gatekeeper:
#   The validation below (shape, extension, size) does NOT and cannot verify code behaviour.
#   The real containment is the systemd stack: PrivateNetwork=true, ProtectSystem=strict,
#   ReadWritePaths=SANDBOX_DIR only, User=sandboxrun, NoNewPrivileges.
#   If any of those confinement directives regress, validation here will NOT save you.
#   The sandbox smoke tests in 07-sandbox.sh are the proof that the boundary holds.
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

ROOT_TEMP=""
cleanup() { [[ -n "$ROOT_TEMP" && -f "$ROOT_TEMP" ]] && rm -f "$ROOT_TEMP"; }
trap cleanup EXIT

# ---- Must run as root ----
[[ "$(id -u)" -eq 0 ]] || die "sandbox-mediator.sh must be run as root (via sudo)."

# ---- Accept basename only — no paths, no slashes ----
RAW="${1:?Usage: sudo $0 <filename> (basename only, no paths)}"
[[ "$RAW" == */* ]] && die "Argument must be a filename, not a path. Got: $RAW"

# ---- Extension check (structural — before touching the file) ----
case "$RAW" in
  *.py|*.sh) ;;
  *) die "Unsupported file type: $RAW — only .py and .sh are allowed." ;;
esac

# ---- Path and existence checks on the staged file ----
STAGED="${STAGING_DIR}/${RAW}"
REAL_STAGING=$(realpath "$STAGING_DIR") || die "Cannot resolve STAGING_DIR."
REAL_STAGED=$(realpath -m "$STAGED") || die "Could not resolve staged path."

# Containment: staged path must be inside STAGING_DIR
# realpath resolves symlinks, so a symlink pointing outside STAGING_DIR will fail here
[[ "$REAL_STAGED" == "$REAL_STAGING/"* ]] || die "Path traversal detected: $REAL_STAGED"

# File must exist
[[ -f "$REAL_STAGED" ]] || die "File not found in staging: $REAL_STAGED"

# Staged path itself must not be a symlink (belt-and-suspenders with the realpath check above)
[[ -L "$STAGED" ]] && die "Symlinks are not permitted in staging: $RAW"

# ---- Take custody: copy to root-owned temp BEFORE any further validation ----
# This eliminates the TOCTOU window. All subsequent validation is on our copy,
# which the inference user cannot modify. The ownership-at-staging is irrelevant now.
ROOT_TEMP=$(mktemp -t sandbox-stage-XXXXXX)
chmod 600 "$ROOT_TEMP"
chown root:root "$ROOT_TEMP"
cp "$REAL_STAGED" "$ROOT_TEMP"
info "Took custody: $RAW → $ROOT_TEMP (root-owned; inference user cannot race)"

# ---- Validate our copy (not the original — no race possible) ----

# Size limit
MAX_BYTES=524288  # 512 KB
FILE_SIZE=$(stat -c%s "$ROOT_TEMP")
[[ "$FILE_SIZE" -le "$MAX_BYTES" ]] || \
  die "File too large: ${FILE_SIZE} bytes (max ${MAX_BYTES}). Split into smaller scripts."

# The copy must not be a symlink (cp of a symlink would copy target content, but verify)
[[ -L "$ROOT_TEMP" ]] && die "Unexpected: temp copy is a symlink — aborting."

info "Validated: $RAW (${FILE_SIZE} bytes)"

# ---- Move temp into SANDBOX_DIR as sandboxrun ----
SANDBOX_DEST="${SANDBOX_DIR}/${RAW}"
mv "$ROOT_TEMP" "$SANDBOX_DEST"
ROOT_TEMP=""   # moved — clear so cleanup trap doesn't try to rm a gone file
chown "${SANDBOX_USER}:${SANDBOX_USER}" "$SANDBOX_DEST"
chmod 500 "$SANDBOX_DEST"   # sandboxrun: read+exec only; not writable by sandboxrun
info "Placed in sandbox: $SANDBOX_DEST"

# ---- Execute under full systemd confinement ----
case "$RAW" in
  *.py) INTERP="python3" ;;
  *.sh) INTERP="bash"    ;;
esac

info "Executing as $SANDBOX_USER with confinement..."
info "  PrivateNetwork=true | ProtectSystem=strict | ReadWritePaths=$SANDBOX_DIR only"

EXEC_EXIT=0
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
  -- "$INTERP" "$SANDBOX_DEST" || EXEC_EXIT=$?

# ---- Clean up sandbox copy ----
rm -f "$SANDBOX_DEST"
info "Execution complete (exit: $EXEC_EXIT). Sandbox copy cleaned up."

exit $EXEC_EXIT
