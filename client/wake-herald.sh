#!/usr/bin/env bash
# ============================================================
# wake-herald.sh — Bring the Herald (gaming-PC inference node) online.
#
# Run this from the WORK PC as part of starting the Digital Brain.  It sends a
# Wake-on-LAN magic packet to the gaming PC and then waits for the inference
# API to answer.  The gaming PC must be configured to boot inference by default
# (the installer does this) so a cold wake lands in inference mode.
#
# Usage:
#   ./client/wake-herald.sh [MAC] [HOST] [PROXY_PORT]
#
# Env overrides (handy when wiring into the Digital Brain startup):
#   HERALD_MAC        NIC MAC of the gaming PC (saved on the inference OS at
#                     /opt/inference-boot/.mac-address after first boot)
#   HERALD_HOST       default: inference-pc.local
#   HERALD_PORT       default: 8080 (nginx OpenAI proxy; use 8081 for raw API)
#   HERALD_BROADCAST  default: 255.255.255.255
#   HERALD_TIMEOUT    seconds to wait for the API (default: 180)
#
# Exit 0 once the API responds; exit 1 on timeout (with diagnostics).
# ============================================================
set -euo pipefail

MAC="${1:-${HERALD_MAC:-}}"
HOST="${2:-${HERALD_HOST:-inference-pc.local}}"
PORT="${3:-${HERALD_PORT:-8080}}"
BROADCAST="${HERALD_BROADCAST:-255.255.255.255}"
TIMEOUT="${HERALD_TIMEOUT:-180}"

if [[ -z "$MAC" ]]; then
  echo "Error: no MAC address. Pass it as the first argument or set HERALD_MAC." >&2
  echo "       The gaming PC's MAC is saved on the inference OS at" >&2
  echo "       /opt/inference-boot/.mac-address (printed during first boot)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WOL="$SCRIPT_DIR/../scripts/wol-wake.sh"

echo "[wake-herald] Sending Wake-on-LAN to $HOST (MAC $MAC)..."
if [[ -x "$WOL" ]]; then
  bash "$WOL" "$MAC" "$BROADCAST" || true
else
  # Self-contained fallback so this hook works even if copied on its own.
  MAC_CLEAN=$(echo "$MAC" | tr -d ':-' | tr '[:upper:]' '[:lower:]')
  if [[ ${#MAC_CLEAN} -eq 12 ]] && command -v python3 >/dev/null 2>&1; then
    MAGIC="ffffffffffff"; for _ in $(seq 1 16); do MAGIC+="$MAC_CLEAN"; done
    python3 - "$MAGIC" "$BROADCAST" <<'PY'
import sys, socket, binascii
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.sendto(binascii.unhexlify(sys.argv[1]), (sys.argv[2], 9))
s.close()
PY
  else
    echo "[wake-herald] WARN: could not send WoL (need scripts/wol-wake.sh or python3)." >&2
  fi
fi

URL="http://$HOST:$PORT/v1/models"
echo "[wake-herald] Waiting up to ${TIMEOUT}s for the inference API at $URL ..."
deadline=$(( $(date +%s) + TIMEOUT ))
until curl -fsS -m 4 "$URL" >/dev/null 2>&1; do
  if (( $(date +%s) >= deadline )); then
    echo "[wake-herald] TIMEOUT: the Herald did not come online within ${TIMEOUT}s." >&2
    echo "  Check, in order:" >&2
    echo "   - BIOS: 'Power On By PCIE/PCI' (or 'Wake on LAN') enabled, 'ErP Ready'/deep sleep disabled." >&2
    echo "   - If the last session was Windows: Fast Startup disabled and 'Wake on Magic Packet' enabled on the NIC." >&2
    echo "   - Inference is the default boot entry (it is, if the installer ran cleanly)." >&2
    echo "   - You are on the same LAN/subnet and $HOST resolves (or use the IP)." >&2
    exit 1
  fi
  sleep 3
done

echo "[wake-herald] Herald online — API ready at http://$HOST:$PORT/v1"
