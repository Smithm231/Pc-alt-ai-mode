#!/usr/bin/env bash
# ============================================================
# curl-example.sh — Chat with the inference PC via curl
# Uses the OpenAI-compatible API on the nginx proxy port.
# Usage: ./client/examples/curl-example.sh [host] [model]
# ============================================================

HOST="${1:-inference-pc.local}"
PORT=8080   # nginx proxy port (change to 8081 to hit llama-server directly)

# Get model ID from /v1/models if not specified
if [[ -z "${2-}" ]]; then
  MODEL=$(curl -sf "http://$HOST:$PORT/v1/models" | jq -r '.data[0].id' 2>/dev/null)
  MODEL="${MODEL:-llama3.2}"
else
  MODEL="$2"
fi

PROMPT="Explain what a GPU inference stack is in two sentences."

echo "Host:   http://$HOST:$PORT"
echo "Model:  $MODEL"
echo "Prompt: $PROMPT"
echo "---"

curl -s "http://$HOST:$PORT/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}],
    \"stream\": false
  }" | jq -r '.choices[0].message.content'
