# Arch Linux Automated Hyprland Installer

A set of simple shell scripts to automate the installation of Arch Linux.

## Files

- `config.json`: Configuration file containing system variables like the installation disk, timezone, hostname, and credentials.
- `core_install.sh`: The main script to run from the Arch live ISO. It partitions the disk, installs the base system, and automatically copies over the post-install configurations.
- `post_install.sh`: A script that runs inside the `chroot` environment. It sets up GRUB, configures locales, users, dotfiles, and installs all the necessary packages for a complete environment.

## Usage

1. Boot into the Arch Linux live USB environment.
2. Ensure you have an active internet connection.
3. Clone or download these files into a directory (e.g. `~/`).
4. Update `config.json` with your desired configuration. If you leave fields empty, the scripts will manually prompt you.
5. Run the core installer script as root:
   ```bash
   ./core_install.sh
   ```

The script will handle partitioning, pacstrap, chroot, and execute the post-installation setup autonomously.

