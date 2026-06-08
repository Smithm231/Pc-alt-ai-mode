#!/usr/bin/env bash
# ============================================================
# 01-base-system.sh — Stage 2 (chroot): base packages + user
# Called automatically by 00-bootstrap.sh inside arch-chroot.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }

# ---- Locale + timezone ----
info "Setting locale and timezone..."
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
apt-get install -y -qq locales
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/default/locale

# ---- Core packages ----
info "Installing base packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  linux-generic linux-headers-generic \
  openssh-server \
  curl wget ca-certificates gnupg \
  ufw \
  avahi-daemon avahi-utils libnss-mdns \
  htop nvtop \
  git \
  python3 python3-pip python3-venv \
  jq \
  net-tools iputils-ping \
  systemd-timesyncd \
  pciutils \
  build-essential

# ---- User ----
info "Creating user: $INFERENCE_USER..."
if ! id "$INFERENCE_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$INFERENCE_USER"
fi

if [[ "$INFERENCE_PASSWORD_HASH" == *"PLACEHOLDER"* ]]; then
  # Fallback: set a temporary password so the system is usable
  echo "${INFERENCE_USER}:inferenceboot" | chpasswd
  echo "WARNING: Using default password 'inferenceboot'. Change immediately!"
else
  usermod -p "$INFERENCE_PASSWORD_HASH" "$INFERENCE_USER"
fi

usermod -aG sudo "$INFERENCE_USER"

# ---- SSH ----
info "Configuring SSH..."
mkdir -p /home/"$INFERENCE_USER"/.ssh
chmod 700 /home/"$INFERENCE_USER"/.ssh
chown "$INFERENCE_USER":"$INFERENCE_USER" /home/"$INFERENCE_USER"/.ssh

if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  echo "$SSH_PUBLIC_KEY" >> /home/"$INFERENCE_USER"/.ssh/authorized_keys
  chmod 600 /home/"$INFERENCE_USER"/.ssh/authorized_keys
  chown "$INFERENCE_USER":"$INFERENCE_USER" /home/"$INFERENCE_USER"/.ssh/authorized_keys
fi

cp /opt/inference-boot/config/sshd_config /etc/ssh/sshd_config.d/inference.conf
sed -i "s|__SSH_PORT__|${SSH_PORT}|g" /etc/ssh/sshd_config.d/inference.conf
systemctl enable ssh

# ---- sudo without password for inference user (optional, useful for scripts) ----
echo "$INFERENCE_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/inference
chmod 440 /etc/sudoers.d/inference

# ---- mDNS ----
if [[ "$ENABLE_MDNS" == "true" ]]; then
  info "Enabling mDNS (Avahi)..."
  cp /opt/inference-boot/config/avahi-daemon.conf /etc/avahi/avahi-daemon.conf
  systemctl enable avahi-daemon
  # NSS mDNS — resolves *.local names
  sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
fi

# ---- Systemd network time ----
systemctl enable systemd-timesyncd

# ---- First-boot setup service ----
info "Installing first-boot service..."
cp /opt/inference-boot/config/inference-firstboot.service /etc/systemd/system/
systemctl enable inference-firstboot.service

# ---- Stage ownership ----
chown -R "$INFERENCE_USER":"$INFERENCE_USER" /opt/inference-boot

info "Base system setup complete."
