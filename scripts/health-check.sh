#!/usr/bin/env bash
# ============================================================
# health-check.sh — Full status check of the inference PC
# Usage: ./scripts/health-check.sh [host]
# ============================================================

HOST="${1:-inference-pc.local}"
LLAMACPP_PORT="${LLAMACPP_PORT:-8081}"
PROXY_PORT="${PROXY_PORT:-8080}"
SSH_PORT="${SSH_PORT:-22}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
warn() { echo -e "  ${YELLOW}?${NC} $*"; }

echo "============================================"
echo " Inference PC health check: $HOST"
echo "============================================"

# ---- Reachability ----
echo ""
echo "Network:"
if ping -c 1 -W 2 "$HOST" >/dev/null 2>&1; then
  ok "Host reachable ($HOST)"
else
  fail "Host unreachable — is the inference PC on and booted to inference OS?"
  exit 1
fi

# ---- SSH ----
echo ""
echo "SSH (port $SSH_PORT):"
if nc -z -w 3 "$HOST" "$SSH_PORT" 2>/dev/null; then
  ok "SSH port open"
else
  fail "SSH port $SSH_PORT not reachable"
fi

# ---- llama-server via OpenAI /v1/models ----
echo ""
echo "llama-server API (port $LLAMACPP_PORT):"
if MODELS_RESP=$(curl -sf --max-time 5 "http://$HOST:$LLAMACPP_PORT/v1/models" 2>/dev/null); then
  ok "llama-server API responding"
  MODEL_COUNT=$(echo "$MODELS_RESP" | jq '.data | length' 2>/dev/null || echo 0)
  if [[ "$MODEL_COUNT" -gt 0 ]]; then
    ok "Models loaded: $MODEL_COUNT"
    echo "$MODELS_RESP" | jq -r '.data[].id' 2>/dev/null | while read -r m; do
      echo "      - $m"
    done
  else
    warn "No models loaded — run: ./scripts/pull-model.sh <repo> <file.gguf> --activate"
  fi
else
  fail "llama-server not responding on port $LLAMACPP_PORT"
  echo "      Check: ssh inference@$HOST 'journalctl -u llama-server -n 30'"
fi

# ---- OpenAI proxy ----
echo ""
echo "OpenAI proxy (port $PROXY_PORT):"
if curl -sf --max-time 5 "http://$HOST:$PROXY_PORT/health" >/dev/null 2>&1; then
  ok "Proxy responding at http://$HOST:$PROXY_PORT/v1/"
else
  warn "Proxy not responding (check nginx or ENABLE_PROXY in install.conf)"
fi

# ---- GPU via SSH ----
echo ""
echo "GPU status (via SSH):"
if GPU_INFO=$(ssh -o ConnectTimeout=4 -o StrictHostKeyChecking=no \
  -p "$SSH_PORT" "inference@$HOST" \
  "rocm-smi --showid --showuse 2>/dev/null || \
   nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null || \
   echo 'GPU tools not found'" 2>/dev/null); then
  ok "GPU info:"
  echo "$GPU_INFO" | while IFS= read -r line; do echo "      $line"; done
else
  warn "Could not retrieve GPU info via SSH"
fi

# ---- llama-server GPU utilisation (via SSH) ----
echo ""
echo "llama-server service status:"
if SVC=$(ssh -o ConnectTimeout=4 -o StrictHostKeyChecking=no \
  -p "$SSH_PORT" "inference@$HOST" \
  "systemctl is-active llama-server 2>/dev/null && \
   journalctl -u llama-server -n 3 --no-pager 2>/dev/null" 2>/dev/null); then
  ok "Service status:"
  echo "$SVC" | while IFS= read -r line; do echo "      $line"; done
else
  warn "Could not query llama-server service via SSH"
fi

echo ""
echo "============================================"
