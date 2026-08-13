#!/bin/bash#!/bin/bash
# post_install.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}Starting Arch Linux Post-Installation Setup...${NC}"

CONFIG_FILE="/root/config.json"
if [ -f "$CONFIG_FILE" ]; then
    TIMEZONE=$(jq -r '.timezone // empty' "$CONFIG_FILE")
    HOSTNAME=$(jq -r '.hostname // empty' "$CONFIG_FILE")
    ROOT_PASSWORD=$(jq -r '.credentials.rootpassword // empty' "$CONFIG_FILE")
    USERNAME=$(jq -r '.credentials.username // empty' "$CONFIG_FILE")
    USER_PASSWORD=$(jq -r '.credentials.password // empty' "$CONFIG_FILE")
fi

# Timezone
if [ -z "$TIMEZONE" ] || [ "$TIMEZONE" == "null" ]; then
    echo -e "${YELLOW}Enter your timezone (e.g., America/New_York, Asia/Kolkata):${NC}"
    read TIMEZONE
fi
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale & Console Font
echo -e "${GREEN}Setting locale and console font...${NC}"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "FONT=sun12x22" > /etc/vconsole.conf

# Hostname
if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" == "null" ]; then
    echo -e "${YELLOW}Enter your desired hostname:${NC}"
    read HOSTNAME
fi
echo "$HOSTNAME" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Root password
if [ -n "$ROOT_PASSWORD" ] && [ "$ROOT_PASSWORD" != "null" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
else
    echo -e "${YELLOW}Set root password:${NC}"
    passwd
fi

# User setup
if [ -z "$USERNAME" ] || [ "$USERNAME" == "null" ]; then
    echo -e "${YELLOW}Enter your new username:${NC}"
    read USERNAME
fi
useradd -m -G wheel -s /bin/zsh "$USERNAME"
if [ -n "$USER_PASSWORD" ] && [ "$USER_PASSWORD" != "null" ]; then
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
else
    echo -e "${YELLOW}Set password for $USERNAME:${NC}"
    passwd "$USERNAME"
fi

# Sudo privileges (uncomment wheel group)
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Temporarily allow passwordless sudo for unattended AUR package installation
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-wheel-nopasswd
# Ensure it gets removed even if the script fails midway (error handling)
trap 'rm -f /etc/sudoers.d/99-wheel-nopasswd' EXIT

# Bootloader (GRUB)
echo -e "${GREEN}Installing and configuring GRUB...${NC}"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install packages from the user's specific list
echo -e "${GREEN}Installing requested packages...${NC}"
PKGS=(
    bluez bluez-utils brightnessctl calf cava cmake docker docker-buildx docker-compose 
    dosfstools e2fsprogs easyeffects firefox go grim hypridle hyprland 
    hyprlock hyprpaper hyprpolkitagent imv intel-media-driver intel-ucode iw kdeconnect kitty 
    kubectl libva-utils linux-headers lsp-plugins-lv2 mako man-db man-pages mesa minikube mpv 
    nemo neovim nodejs npm nvme-cli openssh pipewire-pulse power-profiles-daemon 
    qt5-wayland qt6-wayland rust slurp sof-firmware swaync telegram-desktop texinfo tree 
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd unzip vulkan-intel waybar wev wget 
    wl-clipboard wofi zsh zsh-autocomplete zsh-completions zsh-syntax-highlighting
    gnome-boxes
)

pacman -S --needed --noconfirm "${PKGS[@]}"

# Add user to docker group
usermod -aG docker "$USERNAME"

# Enable services after packages are installed
echo -e "${GREEN}Enabling services...${NC}"
systemctl enable NetworkManager
systemctl enable docker.service || true
systemctl enable bluetooth.service || true

USER_SCRIPT="/home/$USERNAME/user_setup.sh"

cat <<EOF > "$USER_SCRIPT"
#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "\${GREEN}Starting User Environment Setup...\${NC}"

cd ~

# 1. Direct AUR Install
if ! command -v brillo &> /dev/null; then
    echo -e "\${GREEN}Cloning and building Brillo from AUR...\${NC}"
    rm -rf brillo
    git clone https://aur.archlinux.org/brillo.git
    cd brillo
    makepkg -si --noconfirm
    cd ~
    rm -rf brillo
fi
if ! command -v wal &> /dev/null; then
    echo -e "\${GREEN}Cloning and building pywal16 from AUR...\${NC}"
    rm -rf python-pywal16
    git clone https://aur.archlinux.org/python-pywal16.git
    cd python-pywal16
    makepkg -si --noconfirm
    cd ~
    rm -rf python-pywal16
fi

# 2. Dotfiles Management
echo -e "\${GREEN}Cloning and linking dotfiles...\${NC}"
DOTFILES_REPO="https://github.com/shivjeet1/dotfiles.git"

if [ ! -d "\$HOME/dotfiles" ]; then
    git clone "\$DOTFILES_REPO" ~/dotfiles
else
    echo -e "\${YELLOW}Dotfiles repository already exists. Pulling latest changes...\${NC}"
    git -C ~/dotfiles pull
fi

setup_symlinks() {
    echo "Symlinking configuration files..."
    
    mkdir -p ~/.config
    
    # Intelligently symlink directories from dotfiles
    if [ -d "\$HOME/dotfiles/.config" ]; then
        # If there's a direct .config folder, link its contents
        for item in "\$HOME/dotfiles/.config/"*; do
            if [ -e "\$item" ]; then
                ln -sfn "\$item" ~/.config/\$(basename "\$item")
            fi
        done
    else
        # Otherwise, link directories from the root of the repo (like hypr, waybar, kitty)
        for dir in "\$HOME/dotfiles/"*; do
            basename="\$(basename "\$dir")"
            if [ -d "\$dir" ] && [[ "\$basename" != ".git" ]]; then
                ln -sfn "\$dir" ~/.config/"\$basename"
            fi
        done
    fi
    
    # Explicitly handle .zshrc
    if [ -f "\$HOME/dotfiles/.zshrc" ]; then
        ln -sfn "\$HOME/dotfiles/.zshrc" ~/.zshrc
    fi
    
    # Handle wallpaper
    if [ -f "\$HOME/dotfiles/aizen.png" ]; then
        mkdir -p ~/Pictures
        cp "\$HOME/dotfiles/aizen.png" ~/Pictures/
    fi
    
    echo "Symlinking finished."
}

setup_symlinks

# Ensure default shell is zsh just in case useradd missed it
sudo chsh -s "\$(which zsh)" "\$USER" || true

# Generate colors with pywal16
if [ -f "\$HOME/Pictures/aizen.png" ]; then
    echo -e "\${GREEN}Generating colors using pywal16...\${NC}"
    wal -i "\$HOME/Pictures/aizen.png"
fi

echo -e "\${GREEN}User environment setup complete!\${NC}"
EOF

chown "$USERNAME":"$USERNAME" "$USER_SCRIPT"
chmod +x "$USER_SCRIPT"

echo -e "${GREEN}Running user environment setup as $USERNAME...${NC}"
su - "$USERNAME" -c "$USER_SCRIPT"

rm -f "$USER_SCRIPT"

echo -e "${GREEN}Post-installation complete! You can now exit chroot and reboot.${NC}"

# post_install.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}Starting Arch Linux Post-Installation Setup...${NC}"

CONFIG_FILE="/root/config.json"
if [ -f "$CONFIG_FILE" ]; then
    TIMEZONE=$(jq -r '.timezone // empty' "$CONFIG_FILE")
    HOSTNAME=$(jq -r '.hostname // empty' "$CONFIG_FILE")
    ROOT_PASSWORD=$(jq -r '.credentials.rootpassword // empty' "$CONFIG_FILE")
    USERNAME=$(jq -r '.credentials.username // empty' "$CONFIG_FILE")
    USER_PASSWORD=$(jq -r '.credentials.password // empty' "$CONFIG_FILE")
fi

# Timezone
if [ -z "$TIMEZONE" ] || [ "$TIMEZONE" == "null" ]; then
    echo -e "${YELLOW}Enter your timezone (e.g., America/New_York, Asia/Kolkata):${NC}"
    read TIMEZONE
fi
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale & Console Font
echo -e "${GREEN}Setting locale and console font...${NC}"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "FONT=sun12x22" > /etc/vconsole.conf

# Hostname
if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" == "null" ]; then
    echo -e "${YELLOW}Enter your desired hostname:${NC}"
    read HOSTNAME
fi
echo "$HOSTNAME" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Root password
if [ -n "$ROOT_PASSWORD" ] && [ "$ROOT_PASSWORD" != "null" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
else
    echo -e "${YELLOW}Set root password:${NC}"
    passwd
fi

# User setup
if [ -z "$USERNAME" ] || [ "$USERNAME" == "null" ]; then
    echo -e "${YELLOW}Enter your new username:${NC}"
    read USERNAME
fi
useradd -m -G wheel -s /bin/zsh "$USERNAME"
if [ -n "$USER_PASSWORD" ] && [ "$USER_PASSWORD" != "null" ]; then
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
else
    echo -e "${YELLOW}Set password for $USERNAME:${NC}"
    passwd "$USERNAME"
fi

# Sudo privileges (uncomment wheel group)
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Temporarily allow passwordless sudo for unattended AUR package installation
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-wheel-nopasswd
# Ensure it gets removed even if the script fails midway (error handling)
trap 'rm -f /etc/sudoers.d/99-wheel-nopasswd' EXIT

# Bootloader (GRUB)
echo -e "${GREEN}Installing and configuring GRUB...${NC}"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install packages from the user's specific list
echo -e "${GREEN}Installing requested packages...${NC}"
PKGS=(
    bluez bluez-utils brightnessctl calf cava cmake docker docker-buildx docker-compose 
    dosfstools e2fsprogs easyeffects firefox go grim hypridle hyprland 
    hyprlock hyprpaper hyprpolkitagent imv intel-media-driver intel-ucode iw kdeconnect kitty 
    kubectl libva-utils linux-headers lsp-plugins-lv2 mako man-db man-pages mesa minikube mpv 
    nemo neovim nodejs npm nvme-cli openssh pipewire-pulse power-profiles-daemon 
    qt5-wayland qt6-wayland rust slurp sof-firmware swaync telegram-desktop texinfo tree 
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd unzip vulkan-intel waybar wev wget 
    wl-clipboard wofi zsh zsh-autocomplete zsh-completions zsh-syntax-highlighting
    gnome-boxes
)

pacman -S --needed --noconfirm "${PKGS[@]}"

# Add user to docker group
usermod -aG docker "$USERNAME"

# Enable services after packages are installed
echo -e "${GREEN}Enabling services...${NC}"
systemctl enable NetworkManager
systemctl enable docker.service || true
systemctl enable bluetooth.service || true

USER_SCRIPT="/home/$USERNAME/user_setup.sh"

cat <<EOF > "$USER_SCRIPT"
#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "\${GREEN}Starting User Environment Setup...\${NC}"

cd ~

# 1. Direct AUR Install
if ! command -v brillo &> /dev/null; then
    echo -e "\${GREEN}Cloning and building Brillo from AUR...\${NC}"
    rm -rf brillo
    git clone https://aur.archlinux.org/brillo.git
    cd brillo
    makepkg -si --noconfirm
    cd ~
    rm -rf brillo
fi
if ! command -v wal &> /dev/null; then
    echo -e "\${GREEN}Cloning and building pywal16 from AUR...\${NC}"
    rm -rf python-pywal16
    git clone https://aur.archlinux.org/python-pywal16.git
    cd python-pywal16
    makepkg -si --noconfirm
    cd ~
    rm -rf python-pywal16
fi

# 2. Dotfiles Management
echo -e "\${GREEN}Cloning and linking dotfiles...\${NC}"
DOTFILES_REPO="https://github.com/shivjeet1/dotfiles.git"

if [ ! -d "\$HOME/dotfiles" ]; then
    git clone "\$DOTFILES_REPO" ~/dotfiles
else
    echo -e "\${YELLOW}Dotfiles repository already exists. Pulling latest changes...\${NC}"
    git -C ~/dotfiles pull
fi

setup_symlinks() {
    echo "Symlinking configuration files..."
    
    mkdir -p ~/.config
    
    # Intelligently symlink directories from dotfiles
    if [ -d "\$HOME/dotfiles/.config" ]; then
        # If there's a direct .config folder, link its contents
        for item in "\$HOME/dotfiles/.config/"*; do
            if [ -e "\$item" ]; then
                ln -sfn "\$item" ~/.config/\$(basename "\$item")
            fi
        done
    else
        # Otherwise, link directories from the root of the repo (like hypr, waybar, kitty)
        for dir in "\$HOME/dotfiles/"*; do
            basename="\$(basename "\$dir")"
            if [ -d "\$dir" ] && [[ "\$basename" != ".git" ]]; then
                ln -sfn "\$dir" ~/.config/"\$basename"
            fi
        done
    fi
    
    # Explicitly handle .zshrc
    if [ -f "\$HOME/dotfiles/.zshrc" ]; then
        ln -sfn "\$HOME/dotfiles/.zshrc" ~/.zshrc
    fi
    
    # Handle wallpaper
    if [ -f "\$HOME/dotfiles/aizen.png" ]; then
        mkdir -p ~/Pictures
        cp "\$HOME/dotfiles/aizen.png" ~/Pictures/
    fi
    
    echo "Symlinking finished."
}

setup_symlinks

# Ensure default shell is zsh just in case useradd missed it
sudo chsh -s "\$(which zsh)" "\$USER" || true

# Generate colors with pywal16
if [ -f "\$HOME/Pictures/aizen.png" ]; then
    echo -e "\${GREEN}Generating colors using pywal16...\${NC}"
    wal -i "\$HOME/Pictures/aizen.png"
fi

echo -e "\${GREEN}User environment setup complete!\${NC}"
EOF

chown "$USERNAME":"$USERNAME" "$USER_SCRIPT"
chmod +x "$USER_SCRIPT"

echo -e "${GREEN}Running user environment setup as $USERNAME...${NC}"
su - "$USERNAME" -c "$USER_SCRIPT"

rm -f "$USER_SCRIPT"

echo -e "${GREEN}Post-installation complete! You can now exit chroot and reboot.${NC}"

