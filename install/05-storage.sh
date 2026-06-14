#!/usr/bin/env bash
# ============================================================
# 05-storage.sh — Mount SATA SSD and create workspace dirs
#
# Two-drive layout (P5):
#   NVMe  (500GB) — OS, llama.cpp build, active model, scratch vault (this drive)
#   SATA SSD (500GB) — model library, sandbox, backups
#
# The gaming-OS drive is explicitly never mounted.
# ============================================================
set -euo pipefail

CONF="/opt/inference-boot/install/install.conf"
source "$CONF"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[STORE]${NC} $*"; }
warn()  { echo -e "${YELLOW}[STORE]${NC} $*"; }
die()   { echo -e "${RED}[STORE]${NC} $*"; exit 1; }

# ---- Verify the SATA SSD exists ----
if [[ ! -b "$SATA_SSD_DEVICE" ]]; then
  die "SATA SSD device $SATA_SSD_DEVICE not found. Check SATA_SSD_DEVICE in install.conf."
fi

# Sanity check: refuse to mount the TARGET_DRIVE (inference NVMe) as the SSD
SATA_REAL=$(realpath "$SATA_SSD_DEVICE")
NVME_REAL=$(realpath "$TARGET_DRIVE")
if [[ "$SATA_REAL" == "$NVME_REAL"* || "$NVME_REAL" == "$SATA_REAL"* ]]; then
  die "SATA_SSD_DEVICE and TARGET_DRIVE point to the same device — aborting."
fi

info "SATA SSD: $SATA_SSD_DEVICE → $SATA_SSD_MOUNT"
lsblk "$SATA_SSD_DEVICE"

# ---- Format the SATA SSD as the ext4 workspace ----
# Detect any existing filesystem on the disk OR its partitions (a Windows drive
# carries NTFS on a partition, so blkid on the bare disk alone misses it).
EXISTING_FS=$(lsblk -rno FSTYPE "$SATA_SSD_DEVICE" 2>/dev/null | grep -v '^$' | paste -sd, - || true)

wipe_and_format_sata() {
  info "Wiping $SATA_SSD_DEVICE (whole disk)..."
  # Unmount / disarm anything currently using this disk or its partitions.
  for dev in $(lsblk -lnpo NAME "$SATA_SSD_DEVICE" 2>/dev/null); do
    umount "$dev" 2>/dev/null || true
    swapoff "$dev" 2>/dev/null || true
  done
  # Clear partition-table + filesystem signatures (partitions first, then disk).
  for part in $(lsblk -lnpo NAME "$SATA_SSD_DEVICE" 2>/dev/null | tail -n +2); do
    wipefs -aq "$part" 2>/dev/null || true
  done
  wipefs -aq "$SATA_SSD_DEVICE" 2>/dev/null || true
  mkfs.ext4 -L sata-ssd -F "$SATA_SSD_DEVICE"
  info "Formatted $SATA_SSD_DEVICE as ext4."
}

if [[ "${SATA_FORCE_FORMAT:-false}" == "true" ]]; then
  [[ -n "$EXISTING_FS" ]] && warn "SATA_FORCE_FORMAT=true — existing data ($EXISTING_FS) on $SATA_SSD_DEVICE will be DESTROYED."
  wipe_and_format_sata
elif [[ -z "$EXISTING_FS" ]]; then
  info "No filesystem found on $SATA_SSD_DEVICE — formatting ext4..."
  mkfs.ext4 -L sata-ssd -F "$SATA_SSD_DEVICE"
  info "Formatted ext4."
else
  die "Existing filesystem ($EXISTING_FS) on $SATA_SSD_DEVICE — refusing to overwrite. Set SATA_FORCE_FORMAT=true in install.conf to wipe it."
fi

# ---- Mount ----
mkdir -p "$SATA_SSD_MOUNT"
if ! mountpoint -q "$SATA_SSD_MOUNT"; then
  mount "$SATA_SSD_DEVICE" "$SATA_SSD_MOUNT"
  info "Mounted $SATA_SSD_DEVICE at $SATA_SSD_MOUNT"
fi

# ---- Add to fstab (persistent mount) ----
SSD_UUID=$(blkid -s UUID -o value "$SATA_SSD_DEVICE")
FSTAB_ENTRY="UUID=$SSD_UUID  $SATA_SSD_MOUNT  ext4  defaults,noatime  0 2"
if ! grep -q "$SSD_UUID" /etc/fstab; then
  echo "$FSTAB_ENTRY" >> /etc/fstab
  info "Added to /etc/fstab: $FSTAB_ENTRY"
fi

# ---- Create workspace directories ----
# Model library — all GGUF variants for testing (Q4/Q5/Q8, multiple bases)
mkdir -p "$MODELS_DIR"
chown "$INFERENCE_USER":"$INFERENCE_USER" "$MODELS_DIR"
info "Models dir: $MODELS_DIR"

# Write/execute sandbox — ring-fenced for model-generated code (see P6)
mkdir -p "$SANDBOX_DIR"
# Owned by the dedicated sandbox user (created in 07-sandbox.sh)
# Inference user has no write access to sandbox
info "Sandbox dir: $SANDBOX_DIR (ownership set in 07-sandbox.sh)"

# Backups — tools, briefs, iteration history (persistent, NOT the scratch vault)
mkdir -p "$BACKUP_DIR"
chown "$INFERENCE_USER":"$INFERENCE_USER" "$BACKUP_DIR"
info "Backup dir: $BACKUP_DIR"

# ---- Active model directory on NVMe ----
# The active model symlink (ACTIVE_MODEL_LINK) points here from the SSD library.
mkdir -p "$(dirname "$ACTIVE_MODEL_LINK")"
chown -R "$INFERENCE_USER":"$INFERENCE_USER" "$(dirname "$ACTIVE_MODEL_LINK")"
info "Active model link target dir: $(dirname "$ACTIVE_MODEL_LINK")"

info "Storage setup complete."
