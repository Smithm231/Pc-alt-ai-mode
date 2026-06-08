#!/usr/bin/env bash
# ============================================================
# firstboot-run.sh — Orchestrates all first-boot install stages
# Called by inference-firstboot.service on the first real boot.
# ============================================================
set -euo pipefail

LOG="/var/log/inference-firstboot.log"
exec > >(tee -a "$LOG") 2>&1

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

echo "============================================================"
echo " Inference Boot — First-boot setup starting"
echo " $(date)"
echo "============================================================"

chmod +x /opt/inference-boot/install/*.sh
chmod +x /opt/inference-boot/scripts/*.sh

echo "[1/6] GPU drivers..."
bash /opt/inference-boot/install/02-gpu-drivers.sh

echo "[2/6] Storage (SATA SSD mount + workspace dirs)..."
bash /opt/inference-boot/install/05-storage.sh

echo "[3/6] Inference stack (build llama.cpp + service)..."
bash /opt/inference-boot/install/03-inference-stack.sh

echo "[4/6] Scratch vault..."
bash /opt/inference-boot/install/06-scratch-vault.sh

echo "[5/6] Sandbox (ring-fenced execution environment)..."
bash /opt/inference-boot/install/07-sandbox.sh

echo "[6/6] Network / firewall..."
bash /opt/inference-boot/install/04-network.sh

# Re-verify GPU now we're running natively (02 may have only warned in chroot)
if grep -q "PENDING_GPU_VERIFY=true" /opt/inference-boot/.firstboot-state 2>/dev/null; then
  echo "[GPU verify] Confirming gfx1100 on live hardware..."
  if rocminfo 2>/dev/null | grep -qi "gfx1100"; then
    echo "[GPU verify] gfx1100 confirmed."
  else
    echo "[GPU verify] WARNING: gfx1100 not detected by rocminfo on live hardware."
    echo "[GPU verify] Check: rocminfo | grep -i gfx"
    echo "[GPU verify] If HSA_OVERRIDE_GFX_VERSION is needed, verify value in install.conf."
  fi
  sed -i '/PENDING_GPU_VERIFY/d' /opt/inference-boot/.firstboot-state
fi

touch /opt/inference-boot/.firstboot-done

echo ""
echo "============================================================"
echo " First-boot complete!  $(date)"
echo " API endpoint:  http://${HOSTNAME}.local:${LLAMACPP_PORT}/v1/models"
if [[ "$ENABLE_PROXY" == "true" ]]; then
  echo " OpenAI proxy:  http://${HOSTNAME}.local:${PROXY_PORT}/v1"
fi
echo " SSH:           ssh inference@${HOSTNAME}.local"
echo " Active model:  ${ACTIVE_MODEL_LINK}"
echo "============================================================"
