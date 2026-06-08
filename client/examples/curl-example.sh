#!/usr/bin/env bash
# ============================================================
# curl-example.sh — Chat with the inference PC via curl
# Uses the OpenAI-compatible API served by the nginx proxy.
# Usage: ./client/examples/curl-example.sh [host] [model]
# ============================================================

HOST="${1:-inference-pc.local}"
MODEL="${2:-llama3.2}"
PORT=8080   # nginx proxy port (change to 11434 to hit Ollama directly)

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
