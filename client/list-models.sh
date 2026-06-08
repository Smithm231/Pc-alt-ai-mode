#!/usr/bin/env bash
# ============================================================
# list-models.sh — List models available on the inference PC
# Usage: ./client/list-models.sh [host] [port]
# ============================================================

HOST="${1:-inference-pc.local}"
PORT="${2:-11434}"
URL="http://${HOST}:${PORT}/api/tags"

echo "Querying $URL ..."
echo ""

if ! curl -sf "$URL" | jq -r '.models[] | "\(.name)\t\(.size | . / 1073741824 | floor)GB"' 2>/dev/null; then
  echo "No models found or server unreachable."
  echo ""
  echo "Troubleshooting:"
  echo "  1. Is the inference PC powered on?  ping ${HOST}"
  echo "  2. Is Ollama running?  ssh inference@${HOST} 'systemctl status ollama'"
  echo "  3. Pull a model:  ./scripts/pull-model.sh llama3.2"
fi
