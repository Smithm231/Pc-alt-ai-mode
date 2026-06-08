#!/usr/bin/env bash
# ============================================================
# 07-sandbox.sh — Ring-fenced write/execute sandbox (P6)
#
# The Herald can write and execute code.  This sandbox is defence-in-depth:
#   1. Confined to SANDBOX_DIR on the SATA SSD
#   2. Runs as a dedicated low-privilege user (not inference, not root)
#   3. systemd sandboxing directives (ProtectSystem, NoNewPrivileges, etc.)
#   4. No network (PrivateNetwork=true in the exec unit)
#   5. No reach to NVMe OS partition beyond what the exec unit allows
#
# Honest risk statement (do not remove): a model that can write and run
# arbitrary code can attempt to escape — not from malice, but because that
# is what code execution is.  There is no perfect sandbox.  These layers
# make it safe enough for a LAN box under direct human control; they must
# not be described or assumed as total isolation.
#
# Verify systemd sandbox directives against current systemd man pages —
# directive names and behaviour can change between major systemd versions.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[SANDBOX]${NC} $*"; }
warn() { echo -e "${YELLOW}[SANDBOX]${NC} $*"; }

SANDBOX_USER="sandboxrun"

# ---- Dedicated execution user ----
info "Creating sandbox user: $SANDBOX_USER"
if ! id "$SANDBOX_USER" &>/dev/null; then
  useradd \
    --system \
    --no-create-home \
    --shell /usr/sbin/nologin \
    --comment "llama.cpp sandbox execution" \
    "$SANDBOX_USER"
fi

# ---- Sandbox directory ownership ----
# Only the sandbox user can write here.
# The inference user (and model) can request execution via run-sandbox.sh,
# but cannot write to the dir directly — execution only via the wired path.
chown "$SANDBOX_USER":"$SANDBOX_USER" "$SANDBOX_DIR"
chmod 750 "$SANDBOX_DIR"
info "Sandbox dir: $SANDBOX_DIR (owner: $SANDBOX_USER)"

# Allow inference user to read (inspect outputs) but not write
setfacl -m "u:${INFERENCE_USER}:r-x" "$SANDBOX_DIR" 2>/dev/null || \
  warn "setfacl not available — inference user read access relies on group only."

# ---- Install sandbox execution service ----
cp /opt/inference-boot/config/sandbox-exec.service /etc/systemd/system/
sed -i "s|__SANDBOX_USER__|${SANDBOX_USER}|g"  /etc/systemd/system/sandbox-exec.service
sed -i "s|__SANDBOX_DIR__|${SANDBOX_DIR}|g"    /etc/systemd/system/sandbox-exec.service

systemctl daemon-reload
info "Sandbox exec service installed."

# ---- Install bubblewrap for deeper confinement ----
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bubblewrap acl || \
  warn "bubblewrap/acl install failed — falling back to systemd-only confinement."

# ---- Verify sandbox (smoke test) ----
info "Running sandbox escape-prevention smoke tests..."
PASS=0; FAIL=0

# Helper: run a command inside the sandbox via run-sandbox.sh and check outcome
sandbox_test() {
  local desc="$1"; shift
  if /opt/inference-boot/scripts/run-sandbox.sh "$@" >/dev/null 2>&1; then
    echo "  ALLOWED: $desc"
  else
    echo "  BLOCKED (expected): $desc"
  fi
}

# Should be blocked: write outside sandbox dir
TEST_RESULT=$(systemd-run \
  --unit="sandbox-test-$$" \
  --property="User=$SANDBOX_USER" \
  --property="ProtectSystem=strict" \
  --property="ProtectHome=true" \
  --property="PrivateTmp=true" \
  --property="NoNewPrivileges=true" \
  --property="PrivateNetwork=true" \
  --property="ReadWritePaths=$SANDBOX_DIR" \
  --wait --collect \
  bash -c "echo test > /tmp/escape-test" 2>&1 || true)
if echo "$TEST_RESULT" | grep -qi "permission denied\|read-only\|failed"; then
  echo "  BLOCKED (correct): write to /tmp outside sandbox"
  PASS=$((PASS+1))
else
  echo "  WARNING: /tmp write may not be blocked — review PrivateTmp directive"
  FAIL=$((FAIL+1))
fi

# Should be blocked: read /etc/shadow
TEST_RESULT=$(systemd-run \
  --unit="sandbox-shadow-test-$$" \
  --property="User=$SANDBOX_USER" \
  --property="ProtectSystem=strict" \
  --property="ProtectHome=true" \
  --property="PrivateTmp=true" \
  --property="NoNewPrivileges=true" \
  --property="PrivateNetwork=true" \
  --property="ReadWritePaths=$SANDBOX_DIR" \
  --wait --collect \
  cat /etc/shadow 2>&1 || true)
if echo "$TEST_RESULT" | grep -qi "permission denied\|no such file\|failed"; then
  echo "  BLOCKED (correct): read /etc/shadow"
  PASS=$((PASS+1))
else
  echo "  WARNING: /etc/shadow may be readable — review ProtectSystem directive"
  FAIL=$((FAIL+1))
fi

info "Smoke tests: $PASS passed, $FAIL warnings."
[[ "$FAIL" -gt 0 ]] && warn "Review systemd sandbox directives — check current systemd man for syntax changes."

info "Sandbox setup complete."
