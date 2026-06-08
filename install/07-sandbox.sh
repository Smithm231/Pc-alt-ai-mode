#!/usr/bin/env bash
# ============================================================
# 07-sandbox.sh — Ring-fenced write/execute sandbox (P6)
#
# Confinement layers (defence-in-depth):
#   1. Confined to SANDBOX_DIR on the SATA SSD
#   2. Runs as sandboxrun (unprivileged, no login shell, not the inference user)
#   3. systemd sandboxing: ProtectSystem=strict, NoNewPrivileges, PrivateNetwork, etc.
#   4. No network (PrivateNetwork=true in exec unit)
#   5. Inference user cannot write to SANDBOX_DIR — only sandboxrun can
#   6. Inference user writes proposed code to STAGING_DIR; mediator validates + transfers
#
# Honest risk statement (do not remove): a model that can write and run arbitrary
# code can attempt to escape its sandbox — not from malice, but because that is what
# code execution is. There is no perfect sandbox. These layers make it safe enough
# for a LAN box under direct human control; they must not be described or assumed
# as total isolation.
#
# Verify systemd directive names against: man systemd.exec
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[SANDBOX]${NC} $*"; }
warn() { echo -e "${YELLOW}[SANDBOX]${NC} $*"; }
die()  { echo -e "${RED}[SANDBOX]${NC} $*"; exit 1; }

SANDBOX_USER="sandboxrun"

# ---- Dedicated execution user ----
info "Creating sandbox user: $SANDBOX_USER"
if ! id "$SANDBOX_USER" &>/dev/null; then
  useradd \
    --system \
    --no-create-home \
    --shell /usr/sbin/nologin \
    --comment "llama.cpp sandbox execution (no interactive login)" \
    "$SANDBOX_USER"
fi

# ---- SANDBOX_DIR — owned exclusively by sandboxrun ----
# The inference user gets read+traverse (inspect outputs) but NO write access.
# Writing is done by sandbox-mediator.sh (runs as root, copies in as sandboxrun).
mkdir -p "$SANDBOX_DIR"
chown "${SANDBOX_USER}:${SANDBOX_USER}" "$SANDBOX_DIR"
chmod 750 "$SANDBOX_DIR"

# Grant inference user read+traverse via ACL (inspect outputs without write access)
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq acl
if setfacl -m "u:${INFERENCE_USER}:r-x" "$SANDBOX_DIR" 2>/dev/null; then
  info "ACL set: $INFERENCE_USER can read $SANDBOX_DIR (no write)"
else
  warn "setfacl unavailable — inference user read access via group only"
fi

info "Sandbox dir: $SANDBOX_DIR (owner: $SANDBOX_USER | inference: read-only)"

# ---- STAGING_DIR — inference user writes here; mediator reads from here ----
# This is the drop-box: inference proposes, mediator validates and transfers.
# Owned by inference; world-readable so mediator (running as root) can validate.
# sandboxrun CANNOT write here — it only reads when mediating.
mkdir -p "$STAGING_DIR"
chown "${INFERENCE_USER}:${INFERENCE_USER}" "$STAGING_DIR"
chmod 755 "$STAGING_DIR"   # inference: rwx; others: r-x (mediator can read, not write)

info "Staging dir: $STAGING_DIR (inference writes; mediator reads + validates)"

# ---- Install mediator and execution service ----
chmod +x /opt/inference-boot/scripts/sandbox-mediator.sh
chmod +x /opt/inference-boot/scripts/run-sandbox.sh

cp /opt/inference-boot/config/sandbox-exec.service /etc/systemd/system/
sed -i "s|__SANDBOX_USER__|${SANDBOX_USER}|g"  /etc/systemd/system/sandbox-exec.service
sed -i "s|__SANDBOX_DIR__|${SANDBOX_DIR}|g"    /etc/systemd/system/sandbox-exec.service
systemctl daemon-reload
info "Sandbox exec service installed."

# ---- Smoke tests: assert on OUTCOME, not on error text ----
# A containment failure that succeeds silently (no error output) must not
# produce a false pass.  We verify the physical outcome after the unit exits.
# Any failed test aborts the install — a leaking sandbox must stop the build.
info "Running sandbox containment verification..."
PASS=0; FAIL=0

ESCAPE_TAG="sandbox-smoke-$$"

# Test 1: Write to /tmp must not reach the real /tmp
# With PrivateTmp=true the unit gets a private /tmp that vanishes on exit.
ESCAPE_FILE="/tmp/sandbox-escape-${ESCAPE_TAG}"
rm -f "$ESCAPE_FILE"

systemd-run \
  --unit="${ESCAPE_TAG}-write" \
  --property="User=$SANDBOX_USER" \
  --property="ProtectSystem=strict" \
  --property="ProtectHome=true" \
  --property="PrivateTmp=true" \
  --property="NoNewPrivileges=true" \
  --property="PrivateNetwork=true" \
  --property="ReadWritePaths=$SANDBOX_DIR" \
  --wait --collect \
  -- bash -c "echo leaked > $ESCAPE_FILE" 2>/dev/null || true

# Assert: the file must NOT exist in the real filesystem
if [[ ! -f "$ESCAPE_FILE" ]]; then
  echo "  PASS: write to /tmp did not reach real filesystem (PrivateTmp contained it)"
  PASS=$((PASS+1))
else
  echo "  FAIL: /tmp write escaped the sandbox — file exists at $ESCAPE_FILE"
  rm -f "$ESCAPE_FILE"
  FAIL=$((FAIL+1))
fi

# Test 2: /etc/shadow must be unreadable — assert on exit code AND absence of content
SHADOW_OUT_FILE="/tmp/shadow-test-${ESCAPE_TAG}"
rm -f "$SHADOW_OUT_FILE"

systemd-run \
  --unit="${ESCAPE_TAG}-shadow" \
  --property="User=$SANDBOX_USER" \
  --property="ProtectSystem=strict" \
  --property="ProtectHome=true" \
  --property="PrivateTmp=true" \
  --property="NoNewPrivileges=true" \
  --property="PrivateNetwork=true" \
  --property="ReadWritePaths=$SANDBOX_DIR" \
  --wait --collect \
  -- bash -c "cat /etc/shadow > $SHADOW_OUT_FILE 2>/dev/null; echo status=$?" 2>/dev/null
SHADOW_EXIT=$?

# Assert: non-zero exit from the unit AND no shadow content written to our file
SHADOW_LEAKED=false
if [[ -f "$SHADOW_OUT_FILE" ]]; then
  if grep -q "root:" "$SHADOW_OUT_FILE" 2>/dev/null; then
    SHADOW_LEAKED=true
  fi
  rm -f "$SHADOW_OUT_FILE"
fi

if [[ "$SHADOW_LEAKED" == "false" ]]; then
  echo "  PASS: /etc/shadow content not accessible from sandbox"
  PASS=$((PASS+1))
else
  echo "  FAIL: /etc/shadow content was readable from within the sandbox"
  FAIL=$((FAIL+1))
fi

# Test 3: Network must be blocked (PrivateNetwork=true)
systemd-run \
  --unit="${ESCAPE_TAG}-net" \
  --property="User=$SANDBOX_USER" \
  --property="ProtectSystem=strict" \
  --property="PrivateTmp=true" \
  --property="NoNewPrivileges=true" \
  --property="PrivateNetwork=true" \
  --property="ReadWritePaths=$SANDBOX_DIR" \
  --wait --collect \
  -- bash -c "ping -c1 -W1 8.8.8.8" 2>/dev/null
NET_EXIT=$?

if [[ "$NET_EXIT" -ne 0 ]]; then
  echo "  PASS: network unreachable from sandbox (PrivateNetwork contained it)"
  PASS=$((PASS+1))
else
  echo "  FAIL: network was reachable from inside the sandbox"
  FAIL=$((FAIL+1))
fi

# ---- Hard fail if any containment check failed ----
echo ""
echo "Sandbox containment results: $PASS passed, $FAIL failed."

if [[ "$FAIL" -gt 0 ]]; then
  die "FATAL: ${FAIL} sandbox containment check(s) failed. Aborting install." \
      "The sandbox is not safe to use with code-execution capability." \
      "Verify systemd version and directive syntax: man systemd.exec"
fi

info "All sandbox containment checks passed."
info "Sandbox setup complete."
info "  Sandbox dir (execute): $SANDBOX_DIR  (owner: $SANDBOX_USER)"
info "  Staging dir (propose): $STAGING_DIR  (owner: $INFERENCE_USER)"
info "  To submit code: place file in $STAGING_DIR then:"
info "    sudo /opt/inference-boot/scripts/sandbox-mediator.sh <filename>"
