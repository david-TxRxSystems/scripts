# Backup & Restore Script

This script automates the backup and restoration of system configurations, user settings, and installed packages on Ubuntu-based systems.

## Features
- Backup APT, Flatpak, and Snap packages.
- Save GNOME settings, extensions, and user configurations.
- Backup SSH and GPG keys.
- Restore all backed-up data with a single command.

## Prerequisites
Ensure the following tools are installed:
- `dpkg`, `flatpak`, `snap`, `pip`, `npm`, `dconf`, `rsync`

Install missing dependencies using:
```bash
sudo apt install dpkg flatpak snapd python3-pip npm dconf-cli rsync