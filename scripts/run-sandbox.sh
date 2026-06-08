#!/usr/bin/env bash
# ============================================================
# run-sandbox.sh — Execute a script inside the ring-fenced sandbox
#
# Usage: ./scripts/run-sandbox.sh <script-in-sandbox-dir> [args...]
# Example: ./scripts/run-sandbox.sh /media/sata-ssd/sandbox/test.py
#
# The script must reside inside SANDBOX_DIR.  It is executed as the
# sandbox user with full systemd confinement (no network, no OS writes,
# no home dir access, private /tmp).
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

SANDBOX_USER="sandboxrun"

SCRIPT="${1:?Usage: $0 <script-in-sandbox-dir> [args...]}"
shift || true

# Guard: script must be inside SANDBOX_DIR
REAL_SCRIPT=$(realpath "$SCRIPT" 2>/dev/null) || { echo "Script not found: $SCRIPT"; exit 1; }
REAL_SANDBOX=$(realpath "$SANDBOX_DIR")
if [[ "$REAL_SCRIPT" != "$REAL_SANDBOX"/* ]]; then
  echo "ERROR: Script must be inside SANDBOX_DIR ($SANDBOX_DIR)"
  echo "       Attempted path: $REAL_SCRIPT"
  exit 1
fi

# Determine interpreter
case "$REAL_SCRIPT" in
  *.py)  INTERP="python3" ;;
  *.sh)  INTERP="bash" ;;
  *)     INTERP="" ;;       # try direct exec
esac

EXEC_CMD="${INTERP:+$INTERP }${REAL_SCRIPT} $*"

echo "[sandbox] Executing: $EXEC_CMD"
echo "[sandbox] Confined to: $SANDBOX_DIR"
echo "[sandbox] User: $SANDBOX_USER | Network: none | Writeable: sandbox dir only"
echo ""

systemd-run \
  --unit="sandbox-exec-$$" \
  --description="Sandboxed execution: $(basename "$REAL_SCRIPT")" \
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
  -- $EXEC_CMD
