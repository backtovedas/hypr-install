#!/bin/bash
# core_install.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Arch Linux Core Installation...${NC}"

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (or from archiso).${NC}"
  exit 1
fi

# Disk selection
echo -e "${YELLOW}Available disks:${NC}"
lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -E '^/dev/sd|^/dev/nvme|^/dev/vd'

echo -e "\n${YELLOW}Enter the disk you want to install Arch Linux on (e.g., /dev/sda, /dev/nvme0n1):${NC}"
read DISK

if [ ! -b "$DISK" ]; then
    echo -e "${RED}Error: Disk $DISK does not exist.${NC}"
    exit 1
fi

echo -e "${RED}WARNING: ALL DATA ON $DISK WILL BE IRREVERSIBLY ERASED!${NC}"
read -p "Are you sure you want to continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Installation aborted."
    exit 1
fi

# Unmount if anything is mounted (prevent errors)
umount -R /mnt 2>/dev/null || true

# Partitioning using parted
echo -e "${GREEN}Partitioning $DISK using parted...${NC}"
wipefs -af "$DISK"

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart "EFI" fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart "SWAP" linux-swap 513MiB 4609MiB
parted -s "$DISK" mkpart "ROOT" ext4 4609MiB 100%

# Handle NVMe/Loop naming convention (p1, p2, p3 vs 1, 2, 3)
if [[ "$DISK" == *nvme* ]] || [[ "$DISK" == *loop* ]] || [[ "$DISK" == *mmcblk* ]]; then
    PART_PREFIX="${DISK}p"
else
    PART_PREFIX="${DISK}"
fi

EFI_PART="${PART_PREFIX}1"
SWAP_PART="${PART_PREFIX}2"
ROOT_PART="${PART_PREFIX}3"

# Formatting
echo -e "${GREEN}Formatting partitions...${NC}"
mkfs.fat -F32 "$EFI_PART"
mkswap "$SWAP_PART"
swapon "$SWAP_PART"
mkfs.ext4 -F "$ROOT_PART"

# Mounting
echo -e "${GREEN}Mounting partitions...${NC}"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

# Update mirrors
echo -e "${GREEN}Installing reflector and updating mirrors...${NC}"
pacman -Syy --needed --noconfirm reflector curl
curl -LO https://raw.githubusercontent.com/shivjeet1/dotfiles/master/scripts/update-mirrors.sh
chmod +x update-mirrors.sh
./update-mirrors.sh

# Bootstrapping
echo -e "${GREEN}Installing base system (pacstrap)...${NC}"
pacstrap /mnt base linux linux-firmware base-devel git sudo networkmanager grub efibootmgr

# Fstab
echo -e "${GREEN}Generating fstab...${NC}"
genfstab -U /mnt >> /mnt/etc/fstab

# Copy post_install.sh to chroot
if [ -f "./post_install.sh" ]; then
    cp ./post_install.sh /mnt/root/
    chmod +x /mnt/root/post_install.sh
    echo -e "${GREEN}Chrooting into the new system to run post_install.sh...${NC}"
    arch-chroot /mnt /root/post_install.sh
else
    echo -e "${RED}post_install.sh not found in the current directory!${NC}"
    echo "Please copy it to /mnt/root/ manually and run it inside arch-chroot."
fi

echo -e "${GREEN}Core installation complete! You can safely reboot now.${NC}"

