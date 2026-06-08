#!/usr/bin/env bash
# ============================================================
# pull-model.sh — Pull a model onto the inference PC
# Usage: ./scripts/pull-model.sh <model-tag> [host]
# Example: ./scripts/pull-model.sh mistral
#          ./scripts/pull-model.sh deepseek-r1:14b
# ============================================================

MODEL="${1:?Usage: $0 <model-tag> [host]}"
HOST="${2:-inference-pc.local}"
PORT="${OLLAMA_PORT:-11434}"

echo "Pulling '$MODEL' on $HOST ..."

curl -s "http://$HOST:$PORT/api/pull" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$MODEL\"}" | \
while IFS= read -r line; do
  STATUS=$(echo "$line" | jq -r '.status // empty' 2>/dev/null)
  COMPLETED=$(echo "$line" | jq -r '.completed // empty' 2>/dev/null)
  TOTAL=$(echo "$line" | jq -r '.total // empty' 2>/dev/null)

  if [[ -n "$TOTAL" && -n "$COMPLETED" && "$TOTAL" -gt 0 ]]; then
    PCT=$(( COMPLETED * 100 / TOTAL ))
    printf "\r  %s: %d%%   " "$STATUS" "$PCT"
  elif [[ -n "$STATUS" ]]; then
    echo "  $STATUS"
  fi
done

echo ""
echo "Done. Verify with: ./client/list-models.sh $HOST"
