#!/usr/bin/env bash
# ============================================================
# wol-wake.sh — Send Wake-on-LAN magic packet to the inference PC
# Run this from your gaming OS to power on the inference PC.
# Usage: ./scripts/wol-wake.sh <mac-address> [broadcast-ip]
# Example: ./scripts/wol-wake.sh aa:bb:cc:dd:ee:ff
#          ./scripts/wol-wake.sh aa:bb:cc:dd:ee:ff 192.168.1.255
#
# The MAC address is printed during first-boot setup and stored at:
#   /opt/inference-boot/.mac-address  (on the inference OS)
# ============================================================

MAC="${1:?Usage: $0 <mac-address> [broadcast-ip]}"
BROADCAST="${2:-255.255.255.255}"

# Normalize MAC (remove separators)
MAC_CLEAN=$(echo "$MAC" | tr -d ':-' | tr '[:upper:]' '[:lower:]')
[[ ${#MAC_CLEAN} -eq 12 ]] || { echo "Error: invalid MAC address '$MAC'"; exit 1; }

# Build magic packet: 6× 0xFF + 16× MAC
MAGIC="ffffffffffff"
for _ in $(seq 1 16); do MAGIC+="$MAC_CLEAN"; done

echo "Sending WoL magic packet to $MAC (broadcast: $BROADCAST)..."

# Try Python first (most portable), fall back to nc
if command -v python3 >/dev/null 2>&1; then
  python3 - "$MAGIC" "$BROADCAST" <<'PY'
import sys, socket, binascii
magic = binascii.unhexlify(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.sendto(magic, (sys.argv[2], 9))
sock.close()
print("Packet sent.")
PY
elif command -v wakeonlan >/dev/null 2>&1; then
  wakeonlan "$MAC"
else
  echo "Error: install python3 or wakeonlan to send WoL packets."
  exit 1
fi

echo "Wait ~30 seconds, then check: ./scripts/health-check.sh"
