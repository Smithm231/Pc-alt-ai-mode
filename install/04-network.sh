#!/usr/bin/env bash
# ============================================================
# 04-network.sh — Firewall (asymmetric), WoL, network config
#
# Inbound policy:  allow LAN to API + proxy ports only
# Outbound policy: DEFAULT DENY — only Discord API is allowlisted
#
# The Herald node is passive; the work PC calls IN.
# The one outbound voice is the Discord bot.  Everything else is dropped.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[NET]${NC} $*"; }
warn() { echo -e "${YELLOW}[NET]${NC} $*"; }

configure_firewall() {
  info "Configuring UFW firewall (asymmetric: deny-out / restricted-in)..."
  ufw --force reset

  # ---- Defaults ----
  ufw default deny incoming
  ufw default deny outgoing     # P7: egress default-deny

  # ---- Loopback — always permit ----
  ufw allow in  on lo
  ufw allow out on lo

  # ---- Established/related outbound (responses to inbound sessions) ----
  # UFW's before.rules already handles ESTABLISHED,RELATED for output;
  # these rules ensure API response packets reach LAN callers even with
  # default-deny outgoing.
  # (This is handled by the conntrack rule in /etc/ufw/before.rules —
  #  no explicit ufw command needed; it is on by default.)

  # ---- Inbound: SSH ----
  ufw allow in from "$ALLOWED_CIDR" to any port "$SSH_PORT" proto tcp comment "SSH (LAN)"

  # ---- Inbound: llama-server API ----
  ufw allow in from "$ALLOWED_CIDR" to any port "$LLAMACPP_PORT" proto tcp comment "llama-server API (LAN)"

  # ---- Inbound: nginx proxy ----
  if [[ "$ENABLE_PROXY" == "true" ]]; then
    ufw allow in from "$ALLOWED_CIDR" to any port "$PROXY_PORT" proto tcp comment "Inference proxy (LAN)"
  fi

  # ---- Inbound: mDNS ----
  if [[ "$ENABLE_MDNS" == "true" ]]; then
    ufw allow in  5353/udp comment "mDNS inbound"
    ufw allow out 5353/udp comment "mDNS outbound"
  fi

  # ---- Outbound: DNS (needed to resolve Discord hostnames) ----
  ufw allow out 53/tcp comment "DNS"
  ufw allow out 53/udp comment "DNS"

  # ---- Outbound: Discord API (sole allowed external voice) ----
  # Resolve Discord's current IPs and add rules. A systemd timer keeps
  # these fresh.  See scripts/update-discord-ips.sh for the refresh logic.
  if [[ "$ENABLE_EGRESS_DENY" == "true" ]]; then
    info "Seeding initial Discord IP rules..."
    /opt/inference-boot/scripts/update-discord-ips.sh || \
      warn "Discord IP seed failed (no network?) — timer will retry on first boot."
  fi

  # ---- Outbound: NTP (time sync) ----
  ufw allow out 123/udp comment "NTP"

  # ---- Install the Discord IP refresh timer ----
  cp /opt/inference-boot/config/discord-ips-refresh.service /etc/systemd/system/
  cp /opt/inference-boot/config/discord-ips-refresh.timer   /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable discord-ips-refresh.timer

  ufw --force enable
  info "Firewall enabled."
  ufw status verbose
}

configure_wol() {
  if [[ "$ENABLE_WOL" != "true" ]]; then return; fi
  info "Configuring Wake-on-LAN..."
  IFACE=$(ip route 2>/dev/null | awk '/default/{print $5}' | head -1)
  if [[ -z "$IFACE" ]]; then
    warn "No default interface found — skipping WoL."
    return
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ethtool
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
  MAC=$(cat /sys/class/net/"$IFACE"/address 2>/dev/null || echo "unknown")
  echo "$MAC" > /opt/inference-boot/.mac-address
  info "WoL enabled on $IFACE (MAC: $MAC)"
}

configure_netplan() {
  if [[ ! -f /etc/netplan/01-inference.yaml ]]; then
    info "Writing netplan configuration..."
    cp /opt/inference-boot/config/network/10-inference.yaml /etc/netplan/01-inference.yaml
    netplan apply 2>/dev/null || true
  fi
}

configure_firewall
configure_wol
configure_netplan

info "Network setup complete."
