#!/usr/bin/env bash
# ============================================================
# swap-model.sh — Switch the active model and restart llama-server
#
# This script is in the sudoers allowlist and runs as ROOT.
# Every argument is treated as hostile — apply the same input discipline
# as sandbox-mediator.sh (the reference implementation for root-executed scripts).
#
# Usage: sudo /opt/inference-boot/scripts/swap-model.sh <gguf-filename>
#        (filename only — no paths, no symlinks, .gguf extension required)
# Example: sudo /opt/inference-boot/scripts/swap-model.sh Llama-3.1-8B-Q8_0.gguf
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[SWAP]${NC} $*"; }
die()  { echo -e "${RED}[SWAP]${NC} $*"; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "swap-model.sh must run as root (via sudo)."

FILE="${1:?Usage: sudo $0 <gguf-filename> (basename only, .gguf)}"

# ---- Input discipline (this script runs as root — treat every argument as hostile) ----

# Basename only — reject any path component
[[ "$FILE" == */* ]] && die "Filename only, no paths allowed. Got: $FILE"

# Extension: only .gguf is a valid active model
[[ "$FILE" == *.gguf ]] || die "Only .gguf files accepted as active model. Got: $FILE"

# Resolve and confirm containment inside MODELS_DIR
REAL_MODELS=$(realpath "$MODELS_DIR") || die "Cannot resolve MODELS_DIR: $MODELS_DIR"
REAL_SRC=$(realpath -m "${MODELS_DIR}/${FILE}") || die "Cannot resolve source path."
[[ "$REAL_SRC" == "$REAL_MODELS/"* ]] || \
  die "Path traversal rejected: resolved path $REAL_SRC is outside $REAL_MODELS"

# Source must not be a symlink (prevent MODELS_DIR-escape via a planted link)
[[ -L "$REAL_SRC" ]] && die "Symlinks not permitted as model source. Got: $REAL_SRC"

# Source must exist and be a regular file
[[ -f "$REAL_SRC" ]] || die "Model not found in $MODELS_DIR: $FILE"

# ---- Validate that ACTIVE_MODEL_LINK is the expected fixed location ----
# Prevent an attacker from having pre-set ACTIVE_MODEL_LINK (via a rogue install.conf)
# to point at an arbitrary filesystem location that ln -sf would then clobber.
REAL_LINK_DIR=$(realpath -m "$(dirname "$ACTIVE_MODEL_LINK")")
EXPECTED_LINK_DIR=$(realpath -m "/opt/inference-boot/models")
[[ "$REAL_LINK_DIR" == "$EXPECTED_LINK_DIR" ]] || \
  die "ACTIVE_MODEL_LINK ($ACTIVE_MODEL_LINK) is not in the expected directory." \
      "Refusing to write a symlink to an unexpected location."

# ---- Perform the swap ----
info "Swapping active model → $FILE"
ln -sf "$REAL_SRC" "$ACTIVE_MODEL_LINK"
info "Active model link: $ACTIVE_MODEL_LINK → $REAL_SRC"

info "Restarting llama-server..."
systemctl restart llama-server.service
info "Done.  Verify: /opt/inference-boot/scripts/health-check.sh"
