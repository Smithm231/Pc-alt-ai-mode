#!/usr/bin/env bash
# ============================================================
# 03-inference-stack.sh — Build llama.cpp from source and install
# llama-server as a systemd service.
#
# Builds two backends side-by-side:
#   - HIP (AMD ROCm) — primary, for gfx1100 (7900 XTX)
#   - Vulkan         — secondary binary for benchmarking
#
# CMake flag reference (verify against current CMakeLists.txt if build fails):
#   -DGGML_HIP=ON      AMD ROCm/HIP backend  (was -DLLAMA_HIPBLAS=ON before b2000)
#   -DGGML_VULKAN=ON   Vulkan backend        (was -DLLAMA_VULKAN=ON before b2000)
#   -DAMDGPU_TARGETS   Comma-separated gfx targets; gfx1100 = RDNA3 (7900 XTX)
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[LLAMA]${NC} $*"; }
warn()  { echo -e "${YELLOW}[LLAMA]${NC} $*"; }
die()   { echo -e "${RED}[LLAMA]${NC} $*"; exit 1; }

BUILD_CORES=$(nproc)

# ---- Build dependencies ----
install_build_deps() {
  info "Installing build dependencies..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    git cmake ninja-build \
    build-essential pkg-config \
    libcurl4-openssl-dev \
    python3 python3-pip python3-venv \
    huggingface_hub 2>/dev/null || true  # may not be a deb package

  # Install huggingface-cli via pip if apt didn't have it
  if ! command -v huggingface-cli >/dev/null 2>&1; then
    info "Installing huggingface-cli via pip..."
    pip3 install --break-system-packages huggingface_hub 2>/dev/null || \
      pip3 install huggingface_hub
  fi
}

# ---- Clone llama.cpp ----
clone_llamacpp() {
  info "Cloning llama.cpp from ${LLAMACPP_REPO}..."
  if [[ -d "${LLAMACPP_INSTALL_DIR}/.git" ]]; then
    info "Existing clone found — pulling latest..."
    git -C "$LLAMACPP_INSTALL_DIR" pull --ff-only
  else
    git clone --depth=1 "$LLAMACPP_REPO" "$LLAMACPP_INSTALL_DIR"
  fi
}

# ---- Build: HIP (AMD ROCm) backend — primary ----
build_hip() {
  info "Building llama.cpp with HIP (ROCm) backend for ${AMDGPU_TARGETS}..."
  cd "$LLAMACPP_INSTALL_DIR"

  # Locate ROCm
  ROCM_PATH=$(hipconfig --rocmpath 2>/dev/null || echo "/opt/rocm")
  info "ROCm path: $ROCM_PATH"

  # Verify the CMake flag name against the current source before building.
  # GGML_HIP was introduced around b2000; if it doesn't exist, try LLAMA_HIPBLAS.
  if grep -rq "GGML_HIP" CMakeLists.txt ggml/CMakeLists.txt 2>/dev/null; then
    HIP_FLAG="-DGGML_HIP=ON"
  elif grep -rq "LLAMA_HIPBLAS" CMakeLists.txt 2>/dev/null; then
    HIP_FLAG="-DLLAMA_HIPBLAS=ON"
    warn "Falling back to legacy CMake flag LLAMA_HIPBLAS (pre-b2000 build)."
  else
    die "Could not find a known HIP CMake flag in this llama.cpp version."
  fi

  cmake -B build-hip \
    "$HIP_FLAG" \
    -DAMDGPU_TARGETS="${AMDGPU_TARGETS}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DCMAKE_PREFIX_PATH="$ROCM_PATH" \
    -GNinja

  cmake --build build-hip --config Release -j"$BUILD_CORES"

  # Install HIP binaries under a named prefix so they coexist with Vulkan builds
  cmake --install build-hip --prefix /usr/local/llama-hip
  info "HIP build installed to /usr/local/llama-hip/bin/"

  # Primary llama-server symlink
  ln -sf /usr/local/llama-hip/bin/llama-server /usr/local/bin/llama-server
  ln -sf /usr/local/llama-hip/bin/llama-cli    /usr/local/bin/llama-cli
}

# ---- Build: Vulkan backend — secondary for benchmarking ----
build_vulkan() {
  info "Building llama.cpp with Vulkan backend..."
  cd "$LLAMACPP_INSTALL_DIR"

  if grep -rq "GGML_VULKAN" CMakeLists.txt ggml/CMakeLists.txt 2>/dev/null; then
    VK_FLAG="-DGGML_VULKAN=ON"
  elif grep -rq "LLAMA_VULKAN" CMakeLists.txt 2>/dev/null; then
    VK_FLAG="-DLLAMA_VULKAN=ON"
    warn "Falling back to legacy LLAMA_VULKAN flag (pre-b2000 build)."
  else
    warn "No Vulkan CMake flag found in this llama.cpp version — skipping Vulkan build."
    return 0
  fi

  cmake -B build-vulkan \
    "$VK_FLAG" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -GNinja

  cmake --build build-vulkan --config Release -j"$BUILD_CORES"
  cmake --install build-vulkan --prefix /usr/local/llama-vulkan
  info "Vulkan build installed to /usr/local/llama-vulkan/bin/"
  info "To benchmark: llama-server-vulkan vs llama-server (HIP)"

  ln -sf /usr/local/llama-vulkan/bin/llama-server /usr/local/bin/llama-server-vulkan
}

# ---- First-boot model download ----
download_initial_model() {
  if [[ -z "$MODEL_REPO" ]]; then
    warn "MODEL_REPO not set — skipping initial model download."
    warn "Download a model later: ./scripts/pull-model.sh"
    return 0
  fi

  info "Downloading initial model: ${MODEL_REPO} / ${MODEL_FILE}"
  mkdir -p "$MODELS_DIR"

  DEST="${MODELS_DIR}/${MODEL_FILE}"
  if [[ -f "$DEST" ]]; then
    info "Model already present at $DEST — skipping download."
  else
    huggingface-cli download \
      "$MODEL_REPO" \
      "$MODEL_FILE" \
      --local-dir "$MODELS_DIR" \
      --local-dir-use-symlinks False
    info "Model downloaded to $DEST"
  fi

  # Create models dir on NVMe and symlink to SSD model
  mkdir -p "$(dirname "$ACTIVE_MODEL_LINK")"
  ln -sf "$DEST" "$ACTIVE_MODEL_LINK"
  info "Active model symlink: $ACTIVE_MODEL_LINK → $DEST"
}

# ---- systemd service ----
install_service() {
  info "Installing llama-server systemd service..."
  cp /opt/inference-boot/config/llama-server.service /etc/systemd/system/

  # Write the runtime env file that the service reads
  mkdir -p /etc/inference-boot
  cat > /etc/inference-boot/llama-server-env <<EOF
LLAMACPP_HOST=${LLAMACPP_HOST}
LLAMACPP_PORT=${LLAMACPP_PORT}
CTX_SIZE=${CTX_SIZE}
N_GPU_LAYERS=${N_GPU_LAYERS}
N_PARALLEL=${N_PARALLEL}
ACTIVE_MODEL_LINK=${ACTIVE_MODEL_LINK}
EOF
  chmod 640 /etc/inference-boot/llama-server-env
  chown root:"$INFERENCE_USER" /etc/inference-boot/llama-server-env

  # Merge ROCm env if present
  if [[ -f /etc/inference-boot/rocm-env ]]; then
    cat /etc/inference-boot/rocm-env >> /etc/inference-boot/llama-server-env
  fi

  systemctl daemon-reload
  systemctl enable llama-server.service
}

# ---- Optional nginx proxy ----
install_proxy() {
  if [[ "$ENABLE_PROXY" != "true" ]]; then return; fi
  info "Installing nginx OpenAI-compatible proxy on port ${PROXY_PORT}..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx

  cp /opt/inference-boot/config/nginx-inference.conf /etc/nginx/sites-available/inference
  sed -i "s|__PROXY_PORT__|${PROXY_PORT}|g" /etc/nginx/sites-available/inference
  sed -i "s|__LLAMACPP_PORT__|${LLAMACPP_PORT}|g" /etc/nginx/sites-available/inference

  ln -sf /etc/nginx/sites-available/inference /etc/nginx/sites-enabled/inference
  rm -f /etc/nginx/sites-enabled/default

  nginx -t
  systemctl enable nginx
}

# ---- Run ----
install_build_deps
clone_llamacpp
build_hip
build_vulkan
download_initial_model
install_service
install_proxy

info "llama.cpp inference stack setup complete."
info "Binary (HIP):    /usr/local/bin/llama-server"
info "Binary (Vulkan): /usr/local/bin/llama-server-vulkan"
info "Active model:    ${ACTIVE_MODEL_LINK}"
