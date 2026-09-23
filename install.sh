#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# 🌌 HyprQuickShell - Desktop Suite Installer
# Copies configuration files to ~/.config/ and sets permissions.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

# ANSI Color Codes
if [ -t 1 ]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    CYAN="\033[1;36m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    MAGENTA="\033[1;35m"
    RED="\033[1;31m"
    RESET="\033[0m"
else
    BOLD=""
    DIM=""
    CYAN=""
    GREEN=""
    YELLOW=""
    MAGENTA=""
    RED=""
    RESET=""
fi

info()    { echo -e "${CYAN}ℹ [INFO]${RESET} $*"; }
success() { echo -e "${GREEN}✔ [OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}▲ [WARN]${RESET} $*"; }
error()   { echo -e "${RED}✖ [ERROR]${RESET} $*" >&2; }

# Determine script & repository directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${HOME:-/home/$USER}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$TARGET_HOME/.config}"

DO_BACKUP=true
DO_SYMLINK=false
AUTO_YES=false

# Usage / Help
show_help() {
    echo -e "${BOLD}HyprQuickShell Installer${RESET}

${BOLD}Usage:${RESET}
  ./install.sh [options]

${BOLD}Options:${RESET}
  -y, --yes        Proceed with installation automatically without prompt
  -l, --link       Create symbolic links instead of copying files
  -n, --no-backup  Skip backing up existing configuration directories
  -h, --help       Show this help message"
}

# Parse CLI options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -l|--link)
            DO_SYMLINK=true
            shift
            ;;
        -n|--no-backup)
            DO_BACKUP=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  _  _                  ___        _     _     ___ _          _ _ 
 | || |_  _ _ __ _ _ _ / _ \ _  _ (_)___| |__ / __| |_  ___| | |
 | __ | || | '_ \ '_| | (_) | || || / _| / /_\__ \ ' \/ -_) | |
 |_||_|\_, | .__/_|    \__\_\\_,_||_\__|_\_\ |___/_||_\___|_|_|
       |__/|_|                                                
EOF
echo -e "${RESET}"
echo -e "${BOLD}Hyprland & Quickshell Desktop Suite Installation${RESET}"
echo -e "${DIM}Repository: ${SCRIPT_DIR}${RESET}"
echo -e "${DIM}Target:     ${CONFIG_DIR}${RESET}"
echo ""

# ─────────────────────────────────────────────────────────────────
# 1. Dependency Reference
# ─────────────────────────────────────────────────────────────────
echo -e "${MAGENTA}${BOLD}📦 System Dependencies Reference${RESET}"
echo -e "${DIM}Please ensure the following packages are installed on your system:${RESET}"
echo ""
echo -e "  ${BOLD}Core & Compositor:${RESET}  hyprland, kitty, quickshell (or quickshell-git)"
echo -e "  ${BOLD}Theme & Utilities:${RESET}  matugen, python, python-pillow, jq"
echo -e "  ${BOLD}Audio & Media:${RESET}      pipewire, wireplumber, playerctl, cava, pavucontrol, libcanberra"
echo -e "  ${BOLD}System Controls:${RESET}    brightnessctl, networkmanager, bluez, bluez-utils, power-profiles-daemon, hyprsunset"
echo -e "  ${BOLD}Clipboard & Capture:${RESET}grim, slurp, wl-clipboard, cliphist"
echo -e "  ${BOLD}Recommended Fonts:${RESET}  ttf-meslo-nerd-font-powerlevel10k (or any Nerd Font), inter-font"
echo ""
echo -e "${DIM}Quick install command for Arch Linux / CachyOS / EndeavourOS:${RESET}"
echo -e "  ${CYAN}sudo pacman -S --needed hyprland kitty pipewire wireplumber playerctl cava \\"
echo -e "    pavucontrol libcanberra brightnessctl networkmanager bluez bluez-utils \\"
echo -e "    power-profiles-daemon hyprsunset grim slurp wl-clipboard cliphist jq python python-pillow${RESET}"
echo ""
echo -e "${DIM}AUR packages (via yay or paru):${RESET}"
echo -e "  ${CYAN}yay -S --needed quickshell matugen-bin${RESET}"
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo ""

# Confirmation Prompt
if [ "$AUTO_YES" = false ]; then
    echo -ne "${BOLD}Do you want to proceed with the installation? [y/N]: ${RESET}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            echo ""
            ;;
        *)
            echo ""
            warn "Installation aborted by user."
            exit 0
            ;;
    esac
fi


# ─────────────────────────────────────────────────────────────────
# 2. Backup Existing Configurations
# ─────────────────────────────────────────────────────────────────
MODULES=("quickshell" "hypr" "matugen" "theme" "xdg-desktop-portal")

if [ "$DO_BACKUP" = true ]; then
    BACKUP_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="${TARGET_HOME}/.config_backup_${BACKUP_TIMESTAMP}"
    HAS_BACKUP=false

    for mod in "${MODULES[@]}"; do
        if [ -e "${CONFIG_DIR}/${mod}" ]; then
            if [ "$HAS_BACKUP" = false ]; then
                info "Creating backup of existing configurations in: ${BACKUP_DIR}"
                mkdir -p "$BACKUP_DIR"
                HAS_BACKUP=true
            fi
            cp -r "${CONFIG_DIR}/${mod}" "${BACKUP_DIR}/${mod}"
        fi
    done

    if [ "$HAS_BACKUP" = true ]; then
        success "Existing configs safely backed up to ${BACKUP_DIR}"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# 3. Create Required Target Directories
# ─────────────────────────────────────────────────────────────────
info "Ensuring system directories exist..."
mkdir -p "${CONFIG_DIR}"
mkdir -p "${TARGET_HOME}/Pictures/Wallpapers"
mkdir -p "${TARGET_HOME}/Pictures/Screenshots"

# ─────────────────────────────────────────────────────────────────
# 4. Deploy Configuration Files
# ─────────────────────────────────────────────────────────────────
for mod in "${MODULES[@]}"; do
    SRC="${SCRIPT_DIR}/${mod}"
    DEST="${CONFIG_DIR}/${mod}"

    if [ ! -d "$SRC" ]; then
        warn "Source module directory not found: ${SRC} (skipping)"
        continue
    fi

    if [ "$DO_SYMLINK" = true ]; then
        info "Symlinking ${mod} -> ${DEST}"
        rm -rf "$DEST"
        ln -s "$SRC" "$DEST"
        success "Linked ${mod}"
    else
        info "Copying ${mod} -> ${DEST}"
        mkdir -p "$DEST"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a --delete "$SRC/" "$DEST/"
        else
            cp -rT "$SRC" "$DEST"
        fi
        success "Installed ${mod}"
    fi
done

# ─────────────────────────────────────────────────────────────────
# 5. Adapt Hardcoded Paths to Target User Home
# ─────────────────────────────────────────────────────────────────
if [ "$DO_SYMLINK" = false ] && [ "$TARGET_HOME" != "/home/aran" ]; then
    info "Adapting paths to current user home (${TARGET_HOME})..."
    find "${CONFIG_DIR}/quickshell" "${CONFIG_DIR}/hypr" "${CONFIG_DIR}/matugen" -type f \
        \( -name "*.qml" -o -name "*.lua" -o -name "*.toml" -o -name "*.sh" -o -name "*.py" -o -name "*.txt" -o -name "*.json" \) \
        -exec sed -i "s|/home/aran|${TARGET_HOME}|g" {} + 2>/dev/null || true
    success "Paths adapted successfully."
fi

# ─────────────────────────────────────────────────────────────────
# 6. Ensure Scripts Are Executable
# ─────────────────────────────────────────────────────────────────
info "Setting executable permissions on scripts..."
chmod +x "${CONFIG_DIR}/quickshell/scripts/"*.sh "${CONFIG_DIR}/quickshell/scripts/"*.py 2>/dev/null || true
success "Script permissions verified."

# ─────────────────────────────────────────────────────────────────
# 7. Wallpaper Setup & Theme Initialization
# ─────────────────────────────────────────────────────────────────
WP_FILE="${CONFIG_DIR}/quickshell/wallpaper.txt"

# If wallpaper.txt is missing or empty, find or set a default
if [ ! -s "$WP_FILE" ]; then
    FIRST_WP=$(find "${TARGET_HOME}/Pictures/Wallpapers" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \) 2>/dev/null | head -n 1 || true)
    if [ -n "$FIRST_WP" ]; then
        echo "file://${FIRST_WP}" > "$WP_FILE"
        success "Configured wallpaper: ${FIRST_WP}"
    fi
fi

# If matugen is installed and we have a wallpaper, generate initial colors
if command -v matugen >/dev/null 2>&1 && [ -f "${CONFIG_DIR}/quickshell/scripts/matugen.sh" ]; then
    info "Running Matugen theme generator..."
    bash "${CONFIG_DIR}/quickshell/scripts/matugen.sh" >/dev/null 2>&1 || true
    success "Material You color palettes generated."
fi

echo ""
echo -e "${GREEN}${BOLD}🎉 Installation Complete!${RESET}"
echo ""
echo -e "${BOLD}Next Steps:${RESET}"
echo -e "  1. If running Hyprland, reload it:"
echo -e "     ${CYAN}hyprctl reload${RESET}"
echo ""
echo -e "  2. Start or restart Quickshell:"
echo -e "     ${CYAN}killall quickshell 2>/dev/null || true${RESET}"
echo -e "     ${CYAN}quickshell -p ~/.config/quickshell/shell.qml &${RESET}"
echo ""
echo -e "  3. Keybindings:"
echo -e "     • ${BOLD}Alt + Space${RESET}    : Open Spotlight Launcher"
echo -e "     • ${BOLD}Super + M${RESET}      : Open Power Menu"
echo -e "     • ${BOLD}Super + V${RESET}      : Open Clipboard Manager"
echo -e "     • ${BOLD}Super + W${RESET}      : Open Wallpaper Picker"
echo -e "     • ${BOLD}Super + Alt + W${RESET}: Random Wallpaper"
echo ""
