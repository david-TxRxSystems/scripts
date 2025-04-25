#!/bin/bash

BACKUP_DIR="$HOME/system_backup"
LOG_FILE="$BACKUP_DIR/backup_restore.log"
DRY_RUN=false

# Check for dry-run option
if [ "$1" == "--dry-run" ]; then
    DRY_RUN=true
fi

# Redirect output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to check and install dependencies
function check_and_install_dependencies() {
    local dependencies=("dpkg" "flatpak" "snap" "pip" "npm" "dconf-cli" "rsync")
    local missing=()

    echo "🔍 Checking for required dependencies..."
    for cmd in "${dependencies[@]}"; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "✅ All dependencies are installed."
    else
        echo "❌ Missing dependencies: ${missing[*]}"
        echo "🔄 Installing missing dependencies..."
        for pkg in "${missing[@]}"; do
            if [ "$pkg" == "pip" ]; then
                sudo apt install -y python3-pip || { echo "❌ Failed to install $pkg."; exit 1; }
            elif [ "$pkg" == "npm" ]; then
                sudo apt install -y npm || { echo "❌ Failed to install $pkg."; exit 1; }
            else
                sudo apt install -y "$pkg" || { echo "❌ Failed to install $pkg."; exit 1; }
            fi
        done
        echo "✅ All missing dependencies have been installed."
    fi
}

# Trap for cleanup on interruption
trap 'echo "❌ Script interrupted. Cleaning up..."; exit 1' INT TERM

function backup() {
    echo "🔄 Creating backup at $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR" || { echo "❌ Failed to create backup directory."; exit 1; }

    echo "📦 Backing up APT packages..."
    dpkg --get-selections > "$BACKUP_DIR/apt-packages.txt" || { echo "❌ Failed to back up APT packages."; exit 1; }

    echo "📦 Backing up Flatpak packages..."
    flatpak list --app --columns=application > "$BACKUP_DIR/flatpak-packages.txt" || { echo "❌ Failed to back up Flatpak packages."; exit 1; }

    echo "📦 Backing up Snap packages..."
    snap list > "$BACKUP_DIR/snap-packages.txt" || { echo "❌ Failed to back up Snap packages."; exit 1; }

    echo "🔄 Dumping GNOME settings with dconf..."
    dconf dump / > "$BACKUP_DIR/dconf-settings.txt" || { echo "❌ Failed to dump GNOME settings."; exit 1; }

    echo "🧩 Backing up GNOME extensions..."
    mkdir -p "$BACKUP_DIR/gnome_extensions"
    rsync -a ~/.local/share/gnome-shell/extensions/ "$BACKUP_DIR/gnome_extensions/" || { echo "❌ Failed to back up GNOME extensions."; exit 1; }

    echo "🛠️ Backing up dotfiles and personal config..."
    rsync -a ~/.bashrc ~/.zshrc ~/.profile ~/.bash_aliases ~/.gitconfig ~/.tmux.conf ~/.vimrc ~/.inputrc "$BACKUP_DIR/" || { echo "❌ Failed to back up dotfiles."; exit 1; }
    cp ~/.face "$BACKUP_DIR/" 2>/dev/null

    echo "🔐 Backing up SSH and GPG configs..."
    rsync -a ~/.ssh "$BACKUP_DIR/" || { echo "❌ Failed to back up SSH configs."; exit 1; }
    rsync -a ~/.gnupg "$BACKUP_DIR/" || { echo "❌ Failed to back up GPG configs."; exit 1; }

    echo "🎨 Backing up user directories..."
    for dir in ~/.icons ~/.themes ~/.fonts ~/.local/share/applications ~/.config ~/.config/autostart ~/.config/gtk-3.0 ~/.config/gtk-4.0; do
        rsync -a "$dir" "$BACKUP_DIR/" || { echo "❌ Failed to back up $dir."; exit 1; }
    done

    echo "🖼️ Backing up wallpapers..."
    mkdir -p "$BACKUP_DIR/Wallpapers"
    rsync -a ~/Pictures/Wallpaper/ "$BACKUP_DIR/Wallpapers/" || { echo "❌ Failed to back up wallpapers."; exit 1; }

    echo "🐍 Saving pip and npm global packages list..."
    pip list --user > "$BACKUP_DIR/pip-packages.txt" || { echo "❌ Failed to save pip packages."; exit 1; }
    npm list -g --depth=0 > "$BACKUP_DIR/npm-packages.txt" || { echo "❌ Failed to save npm packages."; exit 1; }

    echo "🧩 Saving systemd user units list..."
    systemctl --user list-units --type=service --all > "$BACKUP_DIR/systemd-user-units.txt" || { echo "❌ Failed to save systemd user units."; exit 1; }

    echo "✅ Backup complete."
}

function restore() {
    echo "🔁 Restoring APT packages..."
    if [ -f "$BACKUP_DIR/apt-packages.txt" ]; then
        sudo apt update
        sudo dpkg --set-selections < "$BACKUP_DIR/apt-packages.txt"
        sudo apt-get dselect-upgrade -y || { echo "❌ Failed to restore APT packages."; exit 1; }
    else
        echo "❌ APT packages backup file not found."
    fi

    echo "🔁 Restoring Flatpak packages..."
    if [ -f "$BACKUP_DIR/flatpak-packages.txt" ]; then
        while read -r app; do
            flatpak install -y flathub "$app" || { echo "❌ Failed to install Flatpak package $app."; exit 1; }
        done < "$BACKUP_DIR/flatpak-packages.txt"
    else
        echo "❌ Flatpak packages backup file not found."
    fi

    echo "🔁 Restoring GNOME extensions..."
    rsync -a "$BACKUP_DIR/gnome_extensions/" ~/.local/share/gnome-shell/extensions/ || { echo "❌ Failed to restore GNOME extensions."; exit 1; }

    echo "🔁 Restoring dconf settings..."
    if [ -f "$BACKUP_DIR/dconf-settings.txt" ]; then
        dconf load / < "$BACKUP_DIR/dconf-settings.txt" || { echo "❌ Failed to restore dconf settings."; exit 1; }
    else
        echo "❌ dconf settings backup file not found."
    fi

    echo "🔁 Restoring dotfiles and configs..."
    rsync -a "$BACKUP_DIR/"{.bashrc,.zshrc,.profile,.bash_aliases,.gitconfig,.tmux.conf,.vimrc,.inputrc} ~/ || { echo "❌ Failed to restore dotfiles."; exit 1; }
    cp "$BACKUP_DIR/.face" ~/ 2>/dev/null

    echo "🔁 Restoring SSH and GPG..."
    rsync -a "$BACKUP_DIR/.ssh" ~/ || { echo "❌ Failed to restore SSH configs."; exit 1; }
    rsync -a "$BACKUP_DIR/.gnupg" ~/ || { echo "❌ Failed to restore GPG configs."; exit 1; }
    chmod 700 ~/.ssh ~/.gnupg
    chmod 600 ~/.ssh/* ~/.gnupg/*

    echo "✅ Restore complete."
}

# Main script logic
if [ "$1" == "backup" ]; then
    check_and_install_dependencies
    backup
elif [ "$1" == "restore" ]; then
    check_and_install_dependencies
    restore
else
    echo "Usage: $0 [backup|restore|--dry-run]"
    exit 1
fi