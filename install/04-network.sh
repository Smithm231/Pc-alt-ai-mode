#!/usr/bin/env bash
# ============================================================
# 04-network.sh — Firewall (asymmetric), WoL, network config
#
# Inbound:  allow LAN to SSH/API/proxy ports only
# Outbound: DEFAULT DENY
#   Exceptions: DNS (restricted to one resolver IP), NTP, Cloudflare CIDRs
#               (covers Discord and its CDN), mDNS
#
# Residual outbound channels (conscious decisions, not gaps):
#   1. DNS to $DNS_RESOLVER — needed for Discord resolution; also a potential
#      covert channel (DNS tunnelling) for the inference-user context.
#      The sandbox (PrivateNetwork=true) cannot use this channel at all.
#   2. Cloudflare CIDRs on 443 — wider than strictly Discord, but required for
#      reliable Discord-fronted-by-Cloudflare operation. See update-discord-ips.sh.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[NET]${NC} $*"; }
warn() { echo -e "${YELLOW}[NET]${NC} $*"; }

# ---- Ensure ESTABLISHED,RELATED outbound rule exists in before.rules ----
# Under default-deny-out, API response packets must still reach LAN callers.
# UFW's standard before.rules includes this for INPUT/FORWARD but NOT always OUTPUT.
# We verify and insert explicitly rather than assume the default.
ensure_established_outbound() {
  local BEFORE_RULES="/etc/ufw/before.rules"
  if grep -q "ufw-before-output.*ESTABLISHED\|ufw-before-output.*RELATED" "$BEFORE_RULES" 2>/dev/null; then
    info "ESTABLISHED,RELATED outbound rule already present in $BEFORE_RULES"
  else
    info "Adding ESTABLISHED,RELATED outbound rule to $BEFORE_RULES..."
    # Insert after the loopback output rule (or before COMMIT as fallback)
    if grep -q "\-A ufw-before-output -o lo" "$BEFORE_RULES" 2>/dev/null; then
      sed -i '/\-A ufw-before-output -o lo/a\-A ufw-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT' \
        "$BEFORE_RULES"
    else
      sed -i '/^COMMIT/i\-A ufw-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT' \
        "$BEFORE_RULES"
    fi
    info "Rule added. API responses will reach LAN callers under default-deny-out."
  fi
}

# ---- Resolve DNS resolver IP ----
# Outbound DNS is restricted to this IP only — not allowed to any address.
resolve_dns_ip() {
  if [[ -n "$DNS_RESOLVER" ]]; then
    echo "$DNS_RESOLVER"
    return
  fi
  # Auto-detect: use the default gateway (almost always serves DNS on home LANs)
  local GW
  GW=$(ip route 2>/dev/null | awk '/^default/{print $3}' | head -1)
  if [[ -n "$GW" ]]; then
    echo "$GW"
  else
    # Last resort: fall back to Cloudflare's resolver (at least it's known)
    warn "Cannot detect default gateway — using 1.1.1.1 as DNS resolver."
    echo "1.1.1.1"
  fi
}

configure_firewall() {
  info "Configuring UFW firewall (asymmetric: deny-out / restricted-in)..."
  ufw --force reset

  ensure_established_outbound

  # ---- Defaults ----
  ufw default deny incoming
  ufw default deny outgoing     # P7: egress default-deny

  # ---- Loopback ----
  ufw allow in  on lo
  ufw allow out on lo

  # ---- Inbound: SSH ----
  ufw allow in from "$ALLOWED_CIDR" to any port "$SSH_PORT" proto tcp comment "SSH (LAN)"

  # ---- Inbound: llama-server API ----
  ufw allow in from "$ALLOWED_CIDR" to any port "$LLAMACPP_PORT" proto tcp \
    comment "llama-server API (LAN)"

  # ---- Inbound: nginx proxy ----
  if [[ "$ENABLE_PROXY" == "true" ]]; then
    ufw allow in from "$ALLOWED_CIDR" to any port "$PROXY_PORT" proto tcp \
      comment "Inference proxy (LAN)"
  fi

  # ---- Inbound: mDNS ----
  if [[ "$ENABLE_MDNS" == "true" ]]; then
    ufw allow in  5353/udp comment "mDNS inbound"
    ufw allow out 5353/udp comment "mDNS outbound"
  fi

  # ---- Outbound: DNS restricted to one resolver ----
  # NOT allowed to any — restricts casual DNS tunnelling to arbitrary nameservers.
  # Residual: DNS to this IP is still an outbound channel; recorded in install.conf.
  DNS_IP=$(resolve_dns_ip)
  info "Restricting outbound DNS to resolver: $DNS_IP"
  ufw allow out to "$DNS_IP" port 53 proto tcp comment "DNS (restricted to resolver)"
  ufw allow out to "$DNS_IP" port 53 proto udp comment "DNS (restricted to resolver)"
  echo "$DNS_IP" > /etc/inference-boot/dns-resolver
  info "DNS resolver recorded at /etc/inference-boot/dns-resolver"

  # ---- Outbound: Cloudflare CIDRs on 443 (covers Discord bot traffic) ----
  # Per-host DNS resolution (old approach) was fragile — Cloudflare rotates IPs frequently.
  # Using Cloudflare's published stable CIDR ranges is reliable and matches Discord's CDN.
  # Trade-off: wider than strictly Discord-only, but required for Cloudflare-fronted services.
  # See scripts/update-discord-ips.sh for the range source and fallback logic.
  if [[ "$ENABLE_EGRESS_DENY" == "true" ]]; then
    info "Applying Cloudflare CIDR rules (Discord egress)..."
    /opt/inference-boot/scripts/update-discord-ips.sh || \
      warn "Cloudflare CIDR setup failed (no network?) — timer will apply on first boot."
  fi

  # ---- Outbound: NTP ----
  ufw allow out 123/udp comment "NTP"

  # ---- Install Cloudflare CIDR refresh timer (weekly — CIDRs change rarely) ----
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
info ""
info "Outbound channels (both are residual — documented in install.conf):"
info "  DNS:        $(cat /etc/inference-boot/dns-resolver 2>/dev/null || echo unknown) port 53"
info "  Discord:    Cloudflare CIDRs on port 443 (see: ufw status | grep cloudflare)"
info "  Sandbox:    PrivateNetwork=true — no network access whatsoever"
