#!/usr/bin/env bash
# ============================================================
# firstboot-run.sh — Orchestrates all first-boot install stages
# Called by inference-firstboot.service on the new OS first boot.
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

echo "[1/3] GPU drivers..."
bash /opt/inference-boot/install/02-gpu-drivers.sh

echo "[2/3] Inference stack..."
bash /opt/inference-boot/install/03-inference-stack.sh

echo "[3/3] Network / firewall..."
bash /opt/inference-boot/install/04-network.sh

# Mark done so this never runs again
touch /opt/inference-boot/.firstboot-done

echo ""
echo "============================================================"
echo " First-boot complete!  $(date)"
echo " API endpoint: http://${HOSTNAME}.local:${OLLAMA_PORT}"
if [[ "$ENABLE_PROXY" == "true" ]]; then
  echo " OpenAI proxy:  http://${HOSTNAME}.local:${PROXY_PORT}/v1"
fi
echo "============================================================"
