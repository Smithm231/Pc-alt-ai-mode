#!/usr/bin/env bash
# ============================================================
# 00-bootstrap.sh — Stage 1: partition + debootstrap
#
# Run this from a Ubuntu 22.04/24.04 live USB as root:
#   sudo ./install/00-bootstrap.sh [/dev/nvme1n1]
#
# DANGER: This WILL wipe the target drive.  Double-check TARGET_DRIVE.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONF="$SCRIPT_DIR/install.conf"

# shellcheck source=install.conf
source "$CONF"

# CLI override
if [[ -n "${1-}" ]]; then TARGET_DRIVE="$1"; fi

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---- Sanity checks ----
[[ "$(id -u)" -eq 0 ]] || die "Must run as root."
[[ -b "$TARGET_DRIVE" ]] || die "Target drive $TARGET_DRIVE not found. Check install.conf."

# Confirm before wiping
echo -e "${RED}WARNING: $TARGET_DRIVE will be completely wiped!${NC}"
lsblk "$TARGET_DRIVE"
read -rp "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { info "Aborted."; exit 0; }

# ---- Install deps on live system ----
info "Installing live-system dependencies..."
apt-get update -qq
apt-get install -y -qq debootstrap gdisk arch-install-scripts dosfstools

# ---- Partition table ----
info "Partitioning $TARGET_DRIVE..."
sgdisk --zap-all "$TARGET_DRIVE"
sgdisk \
  -n 1:0:+${EFI_SIZE}MiB  -t 1:ef00 -c 1:"EFI" \
  "$TARGET_DRIVE"

PART_IDX=2
if [[ "$SWAP_SIZE" -gt 0 ]]; then
  sgdisk -n ${PART_IDX}:0:+${SWAP_SIZE}MiB -t ${PART_IDX}:8200 -c ${PART_IDX}:"swap" "$TARGET_DRIVE"
  SWAP_PART="${TARGET_DRIVE}p${PART_IDX}"
  PART_IDX=$((PART_IDX+1))
fi

ROOT_END=$([ "$ROOT_SIZE" -eq 0 ] && echo "0" || echo "+${ROOT_SIZE}MiB")
sgdisk -n ${PART_IDX}:0:${ROOT_END} -t ${PART_IDX}:8300 -c ${PART_IDX}:"root" "$TARGET_DRIVE"
ROOT_PART="${TARGET_DRIVE}p${PART_IDX}"
EFI_PART="${TARGET_DRIVE}p1"

partprobe "$TARGET_DRIVE"
sleep 1

# ---- Format ----
info "Formatting partitions..."
mkfs.fat -F32 -n EFI "$EFI_PART"
mkfs.ext4 -L root -F "$ROOT_PART"
[[ -n "${SWAP_PART-}" ]] && mkswap -L swap "$SWAP_PART"

# ---- Mount ----
MNTPOINT="/mnt/inference-root"
mkdir -p "$MNTPOINT"
mount "$ROOT_PART" "$MNTPOINT"
mkdir -p "$MNTPOINT/boot/efi"
mount "$EFI_PART" "$MNTPOINT/boot/efi"

# ---- Debootstrap Ubuntu 24.04 ----
info "Bootstrapping Ubuntu 24.04 (noble) — this takes a few minutes..."
debootstrap --arch=amd64 noble "$MNTPOINT" http://archive.ubuntu.com/ubuntu

# ---- Basic chroot config ----
info "Writing base configuration..."

# fstab
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
cat > "$MNTPOINT/etc/fstab" <<FSTAB
UUID=$ROOT_UUID  /         ext4  defaults,noatime  0 1
UUID=$EFI_UUID   /boot/efi vfat  umask=0077        0 2
FSTAB
if [[ -n "${SWAP_PART-}" ]]; then
  SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PART")
  echo "UUID=$SWAP_UUID  none  swap  sw  0 0" >> "$MNTPOINT/etc/fstab"
fi

# Hostname
echo "$HOSTNAME" > "$MNTPOINT/etc/hostname"
cat > "$MNTPOINT/etc/hosts" <<HOSTS
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
HOSTS

# APT sources
cat > "$MNTPOINT/etc/apt/sources.list" <<APT
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
APT

# Copy the repo into the new system for stage 2
mkdir -p "$MNTPOINT/opt/inference-boot"
cp -r "$REPO_DIR/." "$MNTPOINT/opt/inference-boot/"
# Save conf values for the chroot stage
cp "$CONF" "$MNTPOINT/opt/inference-boot/install/install.conf"

# ---- Chroot stage 2 ----
info "Entering chroot for stage 2 setup..."
arch-chroot "$MNTPOINT" /opt/inference-boot/install/01-base-system.sh

# ---- Bootloader (dual-boot: inference default, gaming OS selectable) ----
info "Installing GRUB EFI bootloader..."
# os-prober + ntfs-3g let GRUB detect the Windows/gaming OS on the other drive;
# efibootmgr lets us put InferenceBoot first in the firmware boot order.
arch-chroot "$MNTPOINT" bash -c "
  apt-get install -y -qq grub-efi-amd64 grub-efi-amd64-signed shim-signed \
                         efibootmgr os-prober ntfs-3g
  grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id='InferenceBoot' --recheck
"

# ---- GRUB defaults: inference first, menu shown, detect the gaming OS ----
info "Configuring GRUB for inference-default dual boot..."
GRUBCFG="$MNTPOINT/etc/default/grub"
set_grub() {  # key value — set, uncomment, or append a GRUB default
  if grep -q "^$1=" "$GRUBCFG"; then
    sed -i "s|^$1=.*|$1=$2|" "$GRUBCFG"
  elif grep -q "^#\s*$1=" "$GRUBCFG"; then
    sed -i "s|^#\s*$1=.*|$1=$2|" "$GRUBCFG"
  else
    echo "$1=$2" >> "$GRUBCFG"
  fi
}
set_grub GRUB_DISTRIBUTOR '"Inference Boot"'
set_grub GRUB_DEFAULT 0
set_grub GRUB_TIMEOUT "${GRUB_TIMEOUT_SECONDS:-10}"
set_grub GRUB_TIMEOUT_STYLE menu
if [[ "${DETECT_GAMING_OS:-true}" == "true" ]]; then
  set_grub GRUB_DISABLE_OS_PROBER false
fi

# Regenerate the menu — os-prober runs here and should find Windows on the
# other drive (its EFI partition is visible to the chroot).
arch-chroot "$MNTPOINT" update-grub

# ---- Verify the gaming OS made it into the menu ----
if [[ "${DETECT_GAMING_OS:-true}" == "true" ]]; then
  if grep -qiE "menuentry .*(windows|microsoft)" "$MNTPOINT/boot/grub/grub.cfg"; then
    info "Gaming OS (Windows) detected and added to the GRUB menu."
  else
    warn "os-prober did NOT find a Windows/gaming OS on the other drive."
    warn "You can still boot it with your BIOS one-time boot key, or run"
    warn "'sudo update-grub' from the inference OS once both drives are present."
  fi
fi

# ---- Make InferenceBoot the first firmware boot entry ----
# A cold power-on / Wake-on-LAN then lands in inference automatically; the GRUB
# menu still appears for GRUB_TIMEOUT_SECONDS so the gaming OS is one keypress away.
info "Setting InferenceBoot first in the UEFI boot order..."
IB_NUM=$(arch-chroot "$MNTPOINT" efibootmgr 2>/dev/null \
  | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\? .*InferenceBoot.*/\1/p' | head -1)
if [[ -n "${IB_NUM:-}" ]]; then
  CUR_ORDER=$(arch-chroot "$MNTPOINT" efibootmgr 2>/dev/null \
    | sed -n 's/^BootOrder: //p' | head -1)
  NEWORDER="$IB_NUM"
  IFS=',' read -ra ENTRIES <<< "${CUR_ORDER:-}"
  for e in "${ENTRIES[@]}"; do [[ -n "$e" && "$e" != "$IB_NUM" ]] && NEWORDER+=",$e"; done
  arch-chroot "$MNTPOINT" efibootmgr -o "$NEWORDER" >/dev/null 2>&1 \
    && info "UEFI BootOrder set to: $NEWORDER (InferenceBoot=$IB_NUM first)" \
    || warn "Could not set UEFI boot order — set InferenceBoot first in BIOS."
else
  warn "Could not read the InferenceBoot UEFI entry — set boot order in BIOS manually."
fi

# ---- Unmount ----
info "Unmounting..."
umount -R "$MNTPOINT"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} Bootstrap complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  1. Reboot and select 'InferenceBoot' from the BIOS boot menu."
echo "  2. First boot will auto-complete GPU + inference setup (takes ~10 min)."
echo "  3. Access the inference API at:"
echo "     http://${HOSTNAME}.local:${LLAMACPP_PORT}/v1/models"
echo ""
echo "  To switch between gaming OS and inference OS:"
echo "  Set boot order in BIOS/UEFI, or use your BIOS one-time boot key"
echo "  (usually F8, F11, F12, or Del at POST)."
