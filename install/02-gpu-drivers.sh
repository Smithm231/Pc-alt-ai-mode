#!/usr/bin/env bash
# ============================================================
# 02-gpu-drivers.sh — Install AMD ROCm drivers for gfx1100
# Hardened for the Sapphire Nitro+ RX 7900 XTX (gfx1100, RDNA3).
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[GPU]${NC} $*"; }
warn()  { echo -e "${YELLOW}[GPU]${NC} $*"; }
die()   { echo -e "${RED}[GPU]${NC} $*"; exit 1; }

install_rocm() {
  info "Installing AMD ROCm ${ROCM_VERSION}..."
  CODENAME=$(. /etc/os-release && echo "$UBUNTU_CODENAME")
  mkdir -p /etc/apt/keyrings

  # ROCm signing key
  wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | \
    gpg --dearmor > /etc/apt/keyrings/rocm.gpg

  # ROCm package repository
  cat > /etc/apt/sources.list.d/rocm.list <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] \
  https://repo.radeon.com/rocm/apt/${ROCM_VERSION} ${CODENAME} main
EOF

  # Pin ROCm repo higher than distro packages
  cat > /etc/apt/preferences.d/rocm-pin-600 <<EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    rocm-hip-libraries \
    rocminfo \
    rocm-smi-lib \
    hip-runtime-amd \
    rocm-dev

  # Add inference user to render + video groups (required for ROCm GPU access)
  usermod -aG render,video "$INFERENCE_USER"

  info "ROCm ${ROCM_VERSION} installed."
}

verify_gfx1100() {
  info "Verifying GPU is visible to ROCm (rocminfo)..."

  # rocminfo may need the user session to have group membership applied.
  # Running as root here; the GPU should still be accessible via /dev/kfd.
  if ! command -v rocminfo >/dev/null 2>&1; then
    die "rocminfo not found after ROCm install — aborting."
  fi

  if rocminfo 2>/dev/null | grep -qi "gfx1100"; then
    info "gfx1100 confirmed by rocminfo."
  else
    # May not be visible from inside a chroot or live USB environment —
    # issue a warning rather than hard-fail during bootstrap, but the
    # firstboot service will re-run this check on the real hardware.
    warn "gfx1100 NOT detected by rocminfo at this stage."
    warn "If running inside bootstrap/chroot this is expected — GPU is"
    warn "not accessible until the system boots natively on the hardware."
    warn "The firstboot service will verify again on first real boot."
    # Write a flag so firstboot can re-verify
    echo "PENDING_GPU_VERIFY=true" >> /opt/inference-boot/.firstboot-state
  fi
}

write_rocm_env() {
  # Write ROCm environment variables that the llama-server systemd service
  # will inherit.  These are written to a drop-in env file loaded by the
  # service unit — NOT set globally, to avoid leaking into unrelated processes.
  info "Writing ROCm environment for service unit..."

  mkdir -p /etc/inference-boot
  cat > /etc/inference-boot/rocm-env <<EOF
# ROCm environment for the llama-server service.
# HSA_OVERRIDE_GFX_VERSION: required on some ROCm 6.x builds to force
# recognition of gfx1100.  Verify whether the installed ROCm version still
# needs this — newer ROCm may detect gfx1100 automatically.
# Set to empty string in install.conf to disable.
EOF

  if [[ -n "$HSA_OVERRIDE_GFX_VERSION" ]]; then
    echo "HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}" >> /etc/inference-boot/rocm-env
    info "HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION} written."
  else
    info "HSA_OVERRIDE_GFX_VERSION is empty — not set (verify gfx1100 auto-detection)."
  fi

  # Standard ROCm paths
  cat >> /etc/inference-boot/rocm-env <<EOF
HIP_VISIBLE_DEVICES=0
ROCR_VISIBLE_DEVICES=0
EOF

  chmod 644 /etc/inference-boot/rocm-env
}

install_vulkan_dev() {
  # Vulkan dev headers needed to build the Vulkan backend of llama.cpp.
  info "Installing Vulkan development packages..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    libvulkan-dev \
    vulkan-tools \
    glslc \
    mesa-vulkan-drivers
}

# ---- NVIDIA path (retained for portability, not the active path) ----
install_nvidia() {
  warn "NVIDIA path triggered — this build targets AMD.  Check GPU_BACKEND in install.conf."
  apt-get install -y -qq software-properties-common
  add-apt-repository -y ppa:graphics-drivers/ppa
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    nvidia-driver-550 nvidia-cuda-toolkit
  echo -e "nvidia\nnvidia_modeset\nnvidia_uvm\nnvidia_drm" > /etc/modules-load.d/nvidia.conf
}

# ---- Dispatch ----
case "$GPU_BACKEND" in
  amd)
    install_rocm
    install_vulkan_dev
    write_rocm_env
    verify_gfx1100
    ;;
  nvidia)
    install_nvidia
    ;;
  cpu)
    warn "CPU-only mode — no GPU drivers installed.  Inference will be slow."
    ;;
  *)
    die "Unknown GPU_BACKEND='${GPU_BACKEND}'. Valid: amd nvidia cpu"
    ;;
esac

info "GPU driver setup complete."
