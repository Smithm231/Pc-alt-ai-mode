#!/usr/bin/env bash
# ============================================================
# swap-model.sh — Switch the active model and restart llama-server
#
# Usage: ./scripts/swap-model.sh <gguf-filename>
#          (file must exist in MODELS_DIR)
# Example: ./scripts/swap-model.sh Llama-3.1-8B-Instruct-Q8_0.gguf
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

FILE="${1:?Usage: $0 <gguf-filename>}"
SRC="${MODELS_DIR}/${FILE}"

[[ -f "$SRC" ]] || { echo "Not found in $MODELS_DIR: $FILE"; exit 1; }

echo "Swapping active model → $FILE"
ln -sf "$SRC" "$ACTIVE_MODEL_LINK"
echo "Active model link: $ACTIVE_MODEL_LINK → $SRC"

echo "Restarting llama-server..."
systemctl restart llama-server
echo "Done.  Verify: ./scripts/health-check.sh"
