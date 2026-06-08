#!/usr/bin/env bash
# ============================================================
# list-models.sh — List models loaded on the inference PC
# Usage: ./client/list-models.sh [host] [port]
# ============================================================

HOST="${1:-inference-pc.local}"
PORT="${2:-11434}"
URL="http://${HOST}:${PORT}/v1/models"

echo "Querying $URL ..."
echo ""

RESP=$(curl -sf --max-time 5 "$URL" 2>/dev/null) || {
  echo "Server unreachable at $URL"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Is the inference PC on?  ping $HOST"
  echo "  2. Is llama-server running?  ssh inference@$HOST 'systemctl status llama-server'"
  echo "  3. Load a model:  ./scripts/pull-model.sh <repo> <file.gguf> --activate"
  exit 1
}

echo "$RESP" | jq -r '.data[] | "\(.id)"' 2>/dev/null || {
  echo "No models listed."
  echo "Response: $RESP"
}
