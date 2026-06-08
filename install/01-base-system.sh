#!/usr/bin/env bash
# ============================================================
# 01-base-system.sh — Stage 2 (chroot): base packages + user
# Called automatically by 00-bootstrap.sh inside arch-chroot.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

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
  build-essential \
  acl

# ---- User (inference) ----
info "Creating user: $INFERENCE_USER..."
if ! id "$INFERENCE_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$INFERENCE_USER"
fi

# The inference user is NOT added to the 'sudo' group.
# It gets access only to the exact commands in /etc/sudoers.d/inference below.

if [[ -n "$INFERENCE_PASSWORD_HASH" ]]; then
  usermod -p "$INFERENCE_PASSWORD_HASH" "$INFERENCE_USER"
elif [[ -n "$SSH_PUBLIC_KEY" ]]; then
  # No password hash set — lock password and rely on key auth (fine if key is set)
  usermod -L "$INFERENCE_USER"
  warn "No INFERENCE_PASSWORD_HASH set — password locked, SSH key auth required."
else
  die "Neither INFERENCE_PASSWORD_HASH nor SSH_PUBLIC_KEY is set in install.conf." \
      "Set at least one before bootstrapping, or you will be locked out."
fi

# ---- SSH ----
info "Configuring SSH..."
SSH_DIR="/home/${INFERENCE_USER}/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "$INFERENCE_USER":"$INFERENCE_USER" "$SSH_DIR"

if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  echo "$SSH_PUBLIC_KEY" >> "${SSH_DIR}/authorized_keys"
  chmod 600 "${SSH_DIR}/authorized_keys"
  chown "$INFERENCE_USER":"$INFERENCE_USER" "${SSH_DIR}/authorized_keys"
fi

cp /opt/inference-boot/config/sshd_config /etc/ssh/sshd_config.d/inference.conf
sed -i "s|__SSH_PORT__|${SSH_PORT}|g" /etc/ssh/sshd_config.d/inference.conf
systemctl enable ssh

# ---- Scoped sudoers (security boundary — not a convenience) ----
# The inference user gets sudo access to a finite list of exact binaries only.
# NO shells, NO editors, NO interpreters, NO iptables/nft/ufw, NO mount.
# Any command not listed here is DENIED.
# See GTFOBins for the class of commands to never allow.
info "Writing scoped sudoers allowlist..."
cat > /etc/sudoers.d/inference <<SUDOERS
# inference user — narrow allowlist; NOT NOPASSWD:ALL
# This is a security boundary. Every line here is a privilege grant; audit before adding.
# Any command NOT listed here is DENIED.
# Never add: bash sh python3 vim less more awk env find systemctl-edit iptables nft ufw mount su
# For the class of risk, see: https://gtfobins.github.io

# llama-server lifecycle — for pull-model.sh and manual service management.
# Note: swap-model.sh handles systemctl internally (it already runs as root).
${INFERENCE_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start llama-server.service
${INFERENCE_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl stop llama-server.service
${INFERENCE_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl restart llama-server.service
${INFERENCE_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl status llama-server.service

# Sandbox: propose code for mediated execution (drop-box pattern).
# mediator validates, takes custody, moves into SANDBOX_DIR as sandboxrun, confines with systemd.
${INFERENCE_USER} ALL=(root) NOPASSWD: /opt/inference-boot/scripts/sandbox-mediator.sh

# Model swap — input-validated (basename, .gguf, realpath containment, symlink rejection).
${INFERENCE_USER} ALL=(root) NOPASSWD: /opt/inference-boot/scripts/swap-model.sh
SUDOERS
chmod 440 /etc/sudoers.d/inference

# Validate the file is syntactically correct before continuing
visudo -c -f /etc/sudoers.d/inference || die "sudoers syntax error — aborting."

# ---- mDNS ----
if [[ "$ENABLE_MDNS" == "true" ]]; then
  info "Enabling mDNS (Avahi)..."
  cp /opt/inference-boot/config/avahi-daemon.conf /etc/avahi/avahi-daemon.conf
  systemctl enable avahi-daemon
  sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
fi

# ---- Systemd network time ----
systemctl enable systemd-timesyncd

# ---- First-boot setup service ----
info "Installing first-boot service..."
cp /opt/inference-boot/config/inference-firstboot.service /etc/systemd/system/
systemctl enable inference-firstboot.service

# ---- File ownership — principle of least privilege ----
# Scripts and config: root:root (the inference user cannot modify them)
chown -R root:root /opt/inference-boot
chmod -R o-w /opt/inference-boot

# Only the data directories the inference user legitimately writes to:
mkdir -p /opt/inference-boot/scratch-vault \
         /opt/inference-boot/models
chown "$INFERENCE_USER":"$INFERENCE_USER" \
  /opt/inference-boot/scratch-vault \
  /opt/inference-boot/models
chmod 750 /opt/inference-boot/scratch-vault \
          /opt/inference-boot/models

info "Base system setup complete."
