#!/usr/bin/env bash
# ============================================================
# 02-gpu-drivers.sh — Install GPU drivers for inference
# Run as root on the inference OS (called by firstboot service).
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[GPU]${NC} $*"; }
warn()  { echo -e "${YELLOW}[GPU]${NC} $*"; }
die()   { echo -e "${RED}[GPU]${NC} $*"; exit 1; }

detect_gpu() {
  if lspci | grep -qi "NVIDIA"; then
    echo "nvidia"
  elif lspci | grep -qi "AMD.*VGA\|Advanced Micro Devices.*VGA\|Radeon"; then
    echo "amd"
  else
    echo "cpu"
  fi
}

if [[ "$GPU_BACKEND" == "auto" ]]; then
  GPU_BACKEND="$(detect_gpu)"
  info "Auto-detected GPU backend: $GPU_BACKEND"
fi

case "$GPU_BACKEND" in
# ----------------------------------------------------------------
nvidia)
  info "Installing NVIDIA drivers..."
  apt-get install -y -qq software-properties-common
  add-apt-repository -y ppa:graphics-drivers/ppa
  apt-get update -qq

  if [[ -n "$NVIDIA_DRIVER_VERSION" ]]; then
    PKG="nvidia-driver-${NVIDIA_DRIVER_VERSION}"
  else
    # Detect recommended driver
    apt-get install -y -qq ubuntu-drivers-common
    PKG=$(ubuntu-drivers devices 2>/dev/null | awk '/recommended/{print $3}' | head -1)
    [[ -z "$PKG" ]] && PKG="nvidia-driver-550"
  fi

  info "Installing package: $PKG"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    "$PKG" nvidia-cuda-toolkit nvidia-utils-"${PKG##*-}" || \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    nvidia-driver-550 nvidia-cuda-toolkit

  # Persist nvidia modules
  echo -e "nvidia\nnvidia_modeset\nnvidia_uvm\nnvidia_drm" > /etc/modules-load.d/nvidia.conf

  info "NVIDIA driver installed. GPU info after reboot:"
  ;;
# ----------------------------------------------------------------
amd)
  info "Installing AMD ROCm drivers..."

  # ROCm repo
  ROCM_VER="${ROCM_VERSION:-6.1}"
  CODENAME=$(. /etc/os-release && echo "$UBUNTU_CODENAME")
  mkdir -p /etc/apt/keyrings
  wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | \
    gpg --dearmor > /etc/apt/keyrings/rocm.gpg

  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] \
    https://repo.radeon.com/rocm/apt/${ROCM_VER} ${CODENAME} main" \
    > /etc/apt/sources.list.d/rocm.list

  echo "Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600" > /etc/apt/preferences.d/rocm-pin-600

  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    rocm-hip-libraries rocminfo rocm-smi-lib

  # Add user to render/video groups
  usermod -aG render,video "$INFERENCE_USER"

  echo 'ADD_EXTRA_GROUPS=1
EXTRA_GROUPS="render video"' > /etc/adduser.conf.d/rocm

  info "AMD ROCm installed."
  ;;
# ----------------------------------------------------------------
cpu)
  warn "No GPU backend selected — inference will run on CPU only (slow)."
  warn "Edit GPU_BACKEND in install.conf and re-run this script to add GPU support."
  ;;
# ----------------------------------------------------------------
*)
  die "Unknown GPU_BACKEND: $GPU_BACKEND. Valid options: nvidia amd cpu"
  ;;
esac

info "GPU driver setup complete."
