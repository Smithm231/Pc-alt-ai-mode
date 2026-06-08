#!/usr/bin/env bash
# ============================================================
# update-discord-ips.sh — Refresh UFW outbound rules for Discord
#
# Called once during install (04-network.sh) and daily by
# discord-ips-refresh.timer to keep IP rules current.
#
# Discord uses Cloudflare infrastructure.  Its IPs are resolved
# from canonical hostnames rather than hardcoded, because Cloudflare
# IPs do change.  DNS itself is allowed out (port 53) so this
# resolution works under the default-deny egress policy.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

RULE_COMMENT="discord-api"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[DISCORD-IPS]${NC} $*"; }
warn() { echo -e "${YELLOW}[DISCORD-IPS]${NC} $*"; }

# Hostnames that the Discord bot traffic touches
DISCORD_HOSTS=(
  "discord.com"
  "gateway.discord.gg"
  "cdn.discordapp.com"
  "discordapp.com"
)

# Resolve to IPv4 addresses
RESOLVED=()
for host in "${DISCORD_HOSTS[@]}"; do
  while IFS= read -r ip; do
    [[ -n "$ip" ]] && RESOLVED+=("$ip")
  done < <(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u)
done

# Deduplicate
mapfile -t UNIQUE_IPS < <(printf '%s\n' "${RESOLVED[@]}" | sort -u)

if [[ ${#UNIQUE_IPS[@]} -eq 0 ]]; then
  warn "Could not resolve any Discord IPs — DNS may not be available yet."
  warn "The timer will retry.  Outbound to Discord is currently blocked."
  exit 1
fi

info "Resolved ${#UNIQUE_IPS[@]} Discord IPs."

# Remove old Discord rules
while IFS= read -r rule_num; do
  ufw delete "$rule_num" 2>/dev/null || true
done < <(ufw status numbered 2>/dev/null | \
         grep -i "$RULE_COMMENT" | \
         grep -oP '^\[\s*\K[0-9]+' | \
         sort -rn)

# Add fresh rules — outbound HTTPS (443) to each IP
for ip in "${UNIQUE_IPS[@]}"; do
  ufw allow out to "$ip" port 443 proto tcp comment "$RULE_COMMENT" 2>/dev/null || true
  info "  Allowed out → $ip:443"
done

info "Discord IP rules updated."
