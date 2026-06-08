#!/usr/bin/env bash
# ============================================================
# 03-inference-stack.sh — Install Ollama inference engine
# Run as root on the inference OS (called by firstboot service).
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFER]${NC} $*"; }
warn() { echo -e "${YELLOW}[INFER]${NC} $*"; }

# ---- Ollama ----
install_ollama() {
  info "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh

  # Override systemd unit to bind to all interfaces
  mkdir -p /etc/systemd/system/ollama.service.d
  cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST}:${OLLAMA_PORT}"
Environment="OLLAMA_ORIGINS=*"
Environment="HOME=/usr/share/ollama"
EOF

  # Ollama runs as its own user created by installer
  systemctl daemon-reload
  systemctl enable ollama
  systemctl start ollama

  info "Waiting for Ollama to be ready..."
  for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
      info "Ollama is up."
      break
    fi
    sleep 2
  done

  # Pull requested models
  if [[ -n "$MODELS_TO_PULL" ]]; then
    info "Pulling models: $MODELS_TO_PULL"
    for model in $MODELS_TO_PULL; do
      info "  Pulling: $model"
      ollama pull "$model" || warn "  Failed to pull $model — run: ollama pull $model"
    done
  fi
}

# ---- Optional OpenAI-compatible reverse proxy (nginx) ----
install_proxy() {
  if [[ "$ENABLE_PROXY" != "true" ]]; then return; fi
  info "Installing nginx reverse proxy on port ${PROXY_PORT}..."
  apt-get install -y -qq nginx

  cp /opt/inference-boot/config/nginx-inference.conf /etc/nginx/sites-available/inference
  sed -i "s|__PROXY_PORT__|${PROXY_PORT}|g" /etc/nginx/sites-available/inference
  sed -i "s|__OLLAMA_PORT__|${OLLAMA_PORT}|g" /etc/nginx/sites-available/inference

  ln -sf /etc/nginx/sites-available/inference /etc/nginx/sites-enabled/inference
  rm -f /etc/nginx/sites-enabled/default

  nginx -t
  systemctl enable nginx
  systemctl restart nginx
  info "Proxy ready at http://${HOSTNAME}.local:${PROXY_PORT}/v1/"
}

case "$INFERENCE_ENGINE" in
  ollama)
    install_ollama
    install_proxy
    ;;
  *)
    warn "Unknown INFERENCE_ENGINE: $INFERENCE_ENGINE. Only 'ollama' is supported."
    ;;
esac

info "Inference stack setup complete."
