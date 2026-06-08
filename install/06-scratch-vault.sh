#!/usr/bin/env bash
# ============================================================
# 06-scratch-vault.sh — Create scratch vault (disposable session memory)
#
# This is the local model's working-memory scratchpad.
# It is explicitly NOT the canonical Digital Brain vault.
# It lives on the NVMe OS partition; it is NOT backed up.
# It does NOT sync with the work-PC /memory/ store.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[VAULT]${NC} $*"; }

mkdir -p "$SCRATCH_VAULT_DIR"
chown "$INFERENCE_USER":"$INFERENCE_USER" "$SCRATCH_VAULT_DIR"
chmod 750 "$SCRATCH_VAULT_DIR"

# ---- Seed note: provenance boundary, recorded at the data layer ----
cat > "${SCRATCH_VAULT_DIR}/00-ABOUT-THIS-VAULT.md" <<'EOF'
# Scratch Vault — Disposable Session Memory

## What this is

This is the Herald's local scratchpad.  It is a plain folder of Markdown files;
there is no Obsidian installation on this headless server.  The folder can be
opened in Obsidian from another machine if ever needed, but it has no
`.obsidian/` config — that is deliberate.

## What this is NOT

This vault is **NOT** the canonical Digital Brain.  It is **NOT** the work-PC
`/memory/` store.  Nothing here is authoritative or permanent.

## Provenance boundary (hard — do not cross this without explicit promotion)

Information flows **ONE WAY**:

  Work PC `/memory/` (canonical) ← archivist pulls from Herald, writes there
  Herald scratch vault            ← local session memory only, never pushed out

The Herald **never writes to the work-PC vault**.
The archivist on the work PC pulls from the Herald's API and decides what to
promote.  Content in this vault is **not ingested into `/memory/`** unless a
human explicitly copies and reviews it for promotion.

This boundary is recorded here — at the data layer — so it is visible to
anything that reads or processes this folder, not just assumed from context
outside the vault.

## Backup status

This vault is **excluded from backups**.  It is intentionally disposable.
The SSD `backups/` directory does NOT include this path.
If the OS is reinstalled, this vault is lost — that is by design.

## Usage

The model may read and write `.md` files anywhere in this folder.
Notes here are for session continuity only — to maintain focus and context
across interactions within a single running session or across short gaps.
They are not a reliable long-term store.

---
*Created by inference-boot first-boot — $(date -u +%Y-%m-%dT%H:%M:%SZ)*
EOF

# Fix ownership after heredoc write (ran as root)
chown "$INFERENCE_USER":"$INFERENCE_USER" "${SCRATCH_VAULT_DIR}/00-ABOUT-THIS-VAULT.md"

info "Scratch vault created at $SCRATCH_VAULT_DIR"
info "Seed note written: 00-ABOUT-THIS-VAULT.md"
