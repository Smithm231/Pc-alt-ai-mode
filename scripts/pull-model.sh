#!/usr/bin/env bash
# ============================================================
# pull-model.sh — Download a GGUF model from HuggingFace
#
# Usage: ./scripts/pull-model.sh <repo> <filename> [--activate]
# Example:
#   ./scripts/pull-model.sh \
#     bartowski/Llama-3.2-3B-Instruct-GGUF \
#     Llama-3.2-3B-Instruct-Q8_0.gguf \
#     --activate
#
# Models are downloaded into MODELS_DIR on the SATA SSD.
# Pass --activate to point the ACTIVE_MODEL_LINK symlink at the new model
# and restart llama-server.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
[[ -f "$CONF" ]] && source "$CONF"

# Defaults if running remotely without the conf
MODELS_DIR="${MODELS_DIR:-/media/sata-ssd/models}"
ACTIVE_MODEL_LINK="${ACTIVE_MODEL_LINK:-/opt/inference-boot/models/active.gguf}"

REPO="${1:?Usage: $0 <hf-repo> <filename.gguf> [--activate]}"
FILE="${2:?Usage: $0 <hf-repo> <filename.gguf> [--activate]}"
ACTIVATE=false
[[ "${3-}" == "--activate" ]] && ACTIVATE=true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[PULL]${NC} $*"; }
warn() { echo -e "${YELLOW}[PULL]${NC} $*"; }

DEST="${MODELS_DIR}/${FILE}"

if [[ -f "$DEST" ]]; then
  info "Already downloaded: $DEST"
else
  info "Downloading: $REPO / $FILE → $MODELS_DIR"
  mkdir -p "$MODELS_DIR"

  if ! command -v huggingface-cli >/dev/null 2>&1; then
    warn "huggingface-cli not found — installing..."
    pip3 install --break-system-packages huggingface_hub 2>/dev/null || \
      pip3 install huggingface_hub
  fi

  huggingface-cli download \
    "$REPO" \
    "$FILE" \
    --local-dir "$MODELS_DIR" \
    --local-dir-use-symlinks False

  info "Downloaded: $DEST"
fi

if [[ "$ACTIVATE" == "true" ]]; then
  info "Activating: $DEST"
  mkdir -p "$(dirname "$ACTIVE_MODEL_LINK")"
  ln -sf "$DEST" "$ACTIVE_MODEL_LINK"
  info "Active model link → $DEST"

  if systemctl is-active --quiet llama-server 2>/dev/null; then
    info "Restarting llama-server..."
    sudo systemctl restart llama-server.service
    info "Done."
  else
    warn "llama-server not running — start with: sudo systemctl start llama-server.service"
  fi
fi

info "Verify: ./scripts/health-check.sh"
