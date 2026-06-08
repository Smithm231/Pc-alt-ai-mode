#!/usr/bin/env bash
# ============================================================
# connect.sh — SSH into the inference PC from your gaming OS
# Usage: ./client/connect.sh [hostname] [user] [port]
# ============================================================

HOST="${1:-inference-pc.local}"
USER="${2:-inference}"
PORT="${3:-22}"

echo "Connecting to $USER@$HOST:$PORT ..."
ssh -p "$PORT" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    "$USER@$HOST"
