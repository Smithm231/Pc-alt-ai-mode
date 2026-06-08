#!/usr/bin/env bash
# ============================================================
# 04-network.sh — Firewall, WoL, and network hardening
# Run as root on the inference OS (called by firstboot service).
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[NET]${NC} $*"; }

# ---- UFW Firewall ----
if [[ "$ENABLE_FIREWALL" == "true" ]]; then
  info "Configuring UFW firewall..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  # SSH
  ufw allow "${SSH_PORT}/tcp" comment "SSH"

  # Ollama API
  if [[ "$ALLOWED_CIDR" == "0.0.0.0/0" ]]; then
    ufw allow "${OLLAMA_PORT}/tcp" comment "Ollama API"
  else
    ufw allow from "$ALLOWED_CIDR" to any port "$OLLAMA_PORT" proto tcp comment "Ollama API (LAN)"
  fi

  # nginx proxy
  if [[ "$ENABLE_PROXY" == "true" ]]; then
    if [[ "$ALLOWED_CIDR" == "0.0.0.0/0" ]]; then
      ufw allow "${PROXY_PORT}/tcp" comment "Inference proxy"
    else
      ufw allow from "$ALLOWED_CIDR" to any port "$PROXY_PORT" proto tcp comment "Inference proxy (LAN)"
    fi
  fi

  # mDNS (UDP 5353)
  if [[ "$ENABLE_MDNS" == "true" ]]; then
    ufw allow 5353/udp comment "mDNS"
  fi

  ufw --force enable
  info "Firewall enabled."
fi

# ---- Wake-on-LAN ----
if [[ "$ENABLE_WOL" == "true" ]]; then
  info "Configuring Wake-on-LAN..."
  IFACE=$(ip route | awk '/default/{print $5}' | head -1)
  if [[ -n "$IFACE" ]]; then
    apt-get install -y -qq ethtool

    cat > /etc/systemd/system/wol.service <<EOF
[Unit]
Description=Enable Wake-on-LAN on $IFACE
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ethtool -s $IFACE wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable wol.service
    ethtool -s "$IFACE" wol g 2>/dev/null || true
    info "WoL enabled on $IFACE."

    # Save MAC for client reference
    MAC=$(cat /sys/class/net/"$IFACE"/address 2>/dev/null || echo "unknown")
    echo "$MAC" > /opt/inference-boot/.mac-address
    info "MAC address: $MAC  (saved to /opt/inference-boot/.mac-address)"
  else
    info "No default interface found — WoL skipped."
  fi
fi

# ---- Netplan config (if not already managed) ----
if [[ ! -f /etc/netplan/01-inference.yaml ]]; then
  info "Writing netplan configuration..."
  cp /opt/inference-boot/config/network/10-inference.yaml /etc/netplan/01-inference.yaml
  netplan apply 2>/dev/null || true
fi

info "Network setup complete."
