#!/usr/bin/env bash
# ============================================================
# update-discord-ips.sh — Apply Cloudflare CIDR egress rules for Discord
#
# Called once during install (04-network.sh) and weekly by
# discord-ips-refresh.timer.
#
# Approach: use Cloudflare's published stable IP ranges
# (cloudflare.com/ips-v4 and /ips-v6) rather than per-host DNS resolution.
#
# Rationale: Discord is fronted by Cloudflare; the IP a resolution returns
# at any moment is one of many rotating Cloudflare IPs.  A daily DNS snapshot
# will frequently miss the current active IP, silently breaking the bot.
# Cloudflare's published CIDR ranges are stable (announced, not rotated),
# widely used as the standard allowlisting method for Cloudflare-fronted
# services, and change rarely enough that a weekly refresh is sufficient.
#
# Trade-off (recorded, not hidden): allowing Cloudflare CIDRs on 443 is
# wider than strictly Discord-only.  Any Cloudflare-fronted HTTPS service
# would also be reachable.  This is the practical trade-off for reliability;
# the sandbox (PrivateNetwork=true) cannot use any of these routes.
# ============================================================
set -euo pipefail

RULE_COMMENT="cloudflare-discord"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[CF-CIDR]${NC} $*"; }
warn() { echo -e "${YELLOW}[CF-CIDR]${NC} $*"; }

# ---- Cloudflare published range URLs ----
CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

# ---- Hardcoded fallback ranges (current as of June 2026) ----
# Used when the live fetch fails (no network at install time, etc.).
# Source: https://www.cloudflare.com/ips/
FALLBACK_V4=(
  "173.245.48.0/20"
  "103.21.244.0/22"
  "103.22.200.0/22"
  "103.31.4.0/22"
  "141.101.64.0/18"
  "108.162.192.0/18"
  "190.93.240.0/20"
  "188.114.96.0/20"
  "197.234.240.0/22"
  "198.41.128.0/17"
  "162.158.0.0/15"
  "104.16.0.0/13"
  "104.24.0.0/14"
  "172.64.0.0/13"
  "131.0.72.0/22"
)

FALLBACK_V6=(
  "2400:cb00::/32"
  "2606:4700::/32"
  "2803:f800::/32"
  "2405:b500::/32"
  "2405:8100::/32"
  "2a06:98c0::/29"
  "2c0f:f248::/32"
)

# ---- Fetch live ranges or fall back ----
fetch_ranges() {
  local URL="$1"; shift
  local FALLBACK=("$@")

  local RESULT
  if RESULT=$(curl -sf --max-time 10 "$URL" 2>/dev/null); then
    # Validate: should look like CIDR blocks, one per line
    if echo "$RESULT" | grep -qP '^\d+\.\d+\.\d+\.\d+/\d+$|^[0-9a-f:]+/\d+$'; then
      echo "$RESULT"
      return 0
    fi
  fi

  warn "Could not fetch $URL — using hardcoded fallback ranges."
  printf '%s\n' "${FALLBACK[@]}"
}

# ---- Remove old Cloudflare rules ----
remove_old_rules() {
  # Delete in reverse order so rule numbers don't shift
  local rule_nums
  mapfile -t rule_nums < <(
    ufw status numbered 2>/dev/null | \
    grep -i "$RULE_COMMENT" | \
    grep -oP '^\[\s*\K[0-9]+' | \
    sort -rn
  )
  for n in "${rule_nums[@]}"; do
    ufw delete "$n" 2>/dev/null || true
  done
  [[ ${#rule_nums[@]} -gt 0 ]] && info "Removed ${#rule_nums[@]} old $RULE_COMMENT rules."
}

# ---- Apply CIDR rules ----
apply_cidrs() {
  local -n CIDRS=$1
  local LABEL="$2"

  info "Applying ${#CIDRS[@]} $LABEL Cloudflare CIDRs on port 443..."
  local count=0
  for cidr in "${CIDRS[@]}"; do
    [[ -z "$cidr" ]] && continue
    ufw allow out to "$cidr" port 443 proto tcp comment "$RULE_COMMENT" 2>/dev/null && \
      count=$((count+1)) || true
  done
  info "  Applied $count rules."
}

# ---- Main ----
remove_old_rules

# IPv4
mapfile -t V4_RANGES < <(fetch_ranges "$CF_IPV4_URL" "${FALLBACK_V4[@]}")
apply_cidrs V4_RANGES "IPv4"

# IPv6 — only apply if the system has a routable IPv6 address
if ip -6 route 2>/dev/null | grep -q "^default\|::/0"; then
  mapfile -t V6_RANGES < <(fetch_ranges "$CF_IPV6_URL" "${FALLBACK_V6[@]}")
  apply_cidrs V6_RANGES "IPv6"
else
  info "No default IPv6 route — skipping IPv6 Cloudflare rules (deterministic, no surprises)."
fi

info "Cloudflare CIDR rules applied (Discord egress ready)."
info "Verify: ufw status | grep $RULE_COMMENT | head -5"
