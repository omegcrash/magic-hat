#!/usr/bin/env bash
# Magic Hat — Desktop Environment Manager
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Installs or removes the desktop layer on top of Magic Hat server.
# The desktop is optional — Magic Hat is a full server with or without it.
#
# Usage:
#   magichat desktop enable     Install desktop environment + apps
#   magichat desktop disable    Remove desktop, revert to headless server
#   magichat desktop status     Show current mode (server / desktop)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

DESKTOP_MARKER="/etc/magichat/desktop.enabled"

# ── Package groups ────────────────────────────────────────────────────────────

# Desktop environment — GNOME (Fedora's native, best Wayland support)
DESKTOP_CORE=(
    # Display server + desktop
    "@workstation-product-environment"
    "gdm"                           # Display manager (login screen)

    # Override GNOME defaults with better alternatives
    "gnome-terminal"                # Terminal emulator
    "gnome-text-editor"             # Notepad equivalent (simple text editor)
    "gnome-calculator"              # Calculator
    "gnome-calendar"                # Calendar (standalone, Familiar is primary)
    "gnome-clocks"                  # World clocks, alarms, timers
    "gnome-weather"                 # Weather widget
    "gnome-system-monitor"          # Task Manager equivalent
    "gnome-disk-utility"            # Disk management (format, partition, SMART)
    "gnome-screenshot"              # Screenshot tool (Print Screen key)
    "gnome-tweaks"                  # Advanced settings
    "dconf-editor"                  # Registry-style config editor
    "file-roller"                   # Archive manager (zip/tar/7z GUI)
    "evince"                        # PDF viewer
    "eog"                           # Image viewer (Eye of GNOME)
    "baobab"                        # Disk usage analyzer
    "seahorse"                      # Password & key manager (GPG, SSH)
)

# Web browser — the window to the Familiar dashboard
DESKTOP_BROWSER=(
    "firefox"                       # Primary browser
    "chromium"                      # Secondary (some web apps work better)
)

# Multimedia — for previewing content Familiar generates
DESKTOP_MEDIA=(
    "totem"                         # Video player (GNOME Videos)
    "celluloid"                     # MPV frontend (for serious media playback)
    "rhythmbox"                     # Music player
    "cheese"                        # Webcam (for video calls via dashboard)
    "gstreamer1-plugins-base"       # Base codecs
    "gstreamer1-plugins-good"       # Good codecs
    "gstreamer1-plugins-bad-free"   # Extra codecs (free)
    "gstreamer1-plugins-ugly-free"  # Patent-unencumbered codecs
    "gstreamer1-plugin-openh264"    # H.264 video codec
    "pipewire"                      # Modern audio server
    "wireplumber"                   # PipeWire session manager
)

# Creative tools — complement Familiar's Artist job class
DESKTOP_CREATIVE=(
    "gimp"                          # Image editing (Photoshop alternative)
    "inkscape"                      # Vector graphics (Illustrator alternative)
    "blender"                       # 3D modeling (if GPU supports it)
    "shotwell"                      # Photo organizer
    "simple-scan"                   # Scanner utility
)

# Productivity — complement (not replace) Familiar's document skills
DESKTOP_PRODUCTIVITY=(
    "libreoffice-writer"            # Already headless — this adds the GUI
    "libreoffice-calc"
    "libreoffice-impress"
    "libreoffice-draw"              # Diagrams, flowcharts
    "libreoffice-gtk3"              # Native GTK integration
    "thunderbird"                   # Email client (backup to Familiar's email)
)

# Developer tools — for people building skills or customizing
DESKTOP_DEV=(
    "gnome-builder"                 # GNOME IDE
    "gitg"                          # Git GUI
    "meld"                          # Visual diff/merge
    "tilix"                         # Tiling terminal emulator
)

# System utilities
DESKTOP_SYSTEM=(
    "cups"                          # Printing
    "system-config-printer"         # Print setup GUI
    "NetworkManager-wifi"           # WiFi support
    "bluez"                         # Bluetooth
    "gnome-bluetooth"               # Bluetooth GUI
    "flatpak"                       # Flatpak app store (for user-installed apps)
    "gnome-software"                # Software center GUI
    "xdg-utils"                     # Desktop integration (xdg-open, etc.)
    "xdg-desktop-portal-gnome"      # Flatpak + Wayland integration
    "wl-clipboard"                  # Wayland clipboard (wl-copy/wl-paste)
)

# Fonts — extend server font set for desktop rendering
DESKTOP_FONTS=(
    "google-noto-emoji-fonts"       # Emoji support
    "google-noto-sans-cjk-fonts"    # Chinese/Japanese/Korean
    "google-noto-serif-fonts"       # Serif variant
    "mozilla-fira-mono-fonts"       # Programming font
    "jetbrains-mono-fonts-all"      # Popular coding font
    "fontawesome-fonts-all"         # Icons (matches Familiar dashboard)
)

# ── Functions ─────────────────────────────────────────────────────────────────

cmd_status() {
    if [[ -f "${DESKTOP_MARKER}" ]]; then
        echo -e "  Mode: ${GREEN}Desktop${NC} (GNOME)"
        if systemctl is-active --quiet gdm 2>/dev/null; then
            echo -e "  Display Manager: ${GREEN}running${NC}"
        else
            echo -e "  Display Manager: ${YELLOW}installed but not running${NC}"
        fi
        echo "  Disable with: magichat desktop disable"
    else
        echo -e "  Mode: ${CYAN}Server${NC} (headless)"
        echo "  Enable desktop with: magichat desktop enable"
    fi
    echo ""
    echo "  All AI server services run in both modes."
    echo "  The desktop is an optional layer on top."
}

cmd_enable() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: Must run as root (sudo magichat desktop enable)${NC}"
        exit 1
    fi

    if [[ -f "${DESKTOP_MARKER}" ]]; then
        echo "Desktop is already enabled."
        cmd_status
        return
    fi

    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║  Magic Hat — Desktop Installation     ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "  This will install a full GNOME desktop environment"
    echo "  on top of your Magic Hat server."
    echo ""
    echo "  What you get:"
    echo "    - GNOME desktop with Wayland"
    echo "    - Firefox + Chromium (dashboard at localhost)"
    echo "    - LibreOffice (full GUI, not just headless)"
    echo "    - GIMP, Inkscape, Blender (Artist tools)"
    echo "    - Video/audio players, webcam support"
    echo "    - Printer, scanner, Bluetooth, WiFi"
    echo "    - Flatpak app store for anything else"
    echo ""
    echo "  What stays the same:"
    echo "    - All AI services keep running (Ollama, Reflection, etc.)"
    echo "    - Dashboard stays at https://localhost"
    echo "    - CLI commands still work"
    echo "    - Security hardening unchanged"
    echo ""
    echo -e "  ${YELLOW}Estimated download: ~2-3 GB. Disk usage: ~5-7 GB.${NC}"
    echo ""

    read -p "  Continue? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0

    echo ""

    # ── Install packages ──────────────────────────────────────────────────

    echo "[1/7] Installing GNOME desktop environment..."
    dnf install -y "${DESKTOP_CORE[@]}" 2>&1 | tail -3

    echo "[2/7] Installing web browsers..."
    dnf install -y "${DESKTOP_BROWSER[@]}" 2>&1 | tail -3

    echo "[3/7] Installing multimedia..."
    dnf install -y "${DESKTOP_MEDIA[@]}" 2>&1 | tail -3

    echo "[4/7] Installing creative tools..."
    dnf install -y "${DESKTOP_CREATIVE[@]}" 2>&1 | tail -3 || {
        echo "  Some creative tools skipped (may require RPM Fusion)"
    }

    echo "[5/7] Installing productivity tools..."
    dnf install -y "${DESKTOP_PRODUCTIVITY[@]}" 2>&1 | tail -3

    echo "[6/7] Installing developer tools & system utilities..."
    dnf install -y "${DESKTOP_DEV[@]}" "${DESKTOP_SYSTEM[@]}" 2>&1 | tail -3 || true

    echo "[7/7] Installing fonts..."
    dnf install -y "${DESKTOP_FONTS[@]}" 2>&1 | tail -3 || true

    # ── Configure ─────────────────────────────────────────────────────────

    # Set graphical target
    systemctl set-default graphical.target

    # Enable display manager
    systemctl enable gdm

    # Set up Flatpak (Flathub) for user app installs
    if command -v flatpak &>/dev/null; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    fi

    # Create a desktop shortcut to the Familiar dashboard
    DESKTOP_DIR="/usr/share/applications"
    cat > "${DESKTOP_DIR}/familiar-dashboard.desktop" << 'EOF'
[Desktop Entry]
Name=Familiar Dashboard
Comment=Open the Familiar AI Dashboard
Exec=xdg-open http://localhost
Icon=applications-science
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
EOF

    # Create a desktop shortcut for the Magic Hat terminal
    cat > "${DESKTOP_DIR}/magichat-terminal.desktop" << 'EOF'
[Desktop Entry]
Name=Magic Hat Terminal
Comment=Magic Hat server management
Exec=gnome-terminal -- bash -c "magichat status; exec bash"
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=System;
StartupNotify=true
EOF

    # Set Firefox homepage to dashboard
    mkdir -p /etc/firefox/policies
    cat > /etc/firefox/policies/policies.json << 'EOF'
{
    "policies": {
        "Homepage": {
            "URL": "http://localhost",
            "StartPage": "homepage"
        },
        "DisplayBookmarksToolbar": "always",
        "ManagedBookmarks": [
            {"toplevel_name": "Magic Hat"},
            {"url": "http://localhost", "name": "Familiar Dashboard"},
            {"url": "http://localhost:22300", "name": "Joplin Notes"},
            {"url": "http://localhost:3000", "name": "Gitea"},
            {"url": "http://localhost:9925", "name": "Mealie Recipes"}
        ]
    }
}
EOF

    # Remove WiFi firmware blacklist from kickstart (if present)
    # The server kickstart removes these — add them back for desktop
    dnf install -y iwl*firmware* wpa_supplicant 2>/dev/null || true

    # Mark desktop as enabled
    mkdir -p /etc/magichat
    echo "enabled=$(date -Iseconds)" > "${DESKTOP_MARKER}"

    echo ""
    echo -e "  ${GREEN}Desktop installed!${NC}"
    echo ""
    echo "  To start the desktop now:"
    echo "    sudo systemctl start gdm"
    echo ""
    echo "  Or reboot to boot into the desktop:"
    echo "    sudo reboot"
    echo ""
    echo "  Your Familiar dashboard will be bookmarked in Firefox."
    echo "  All server services continue running in the background."
    echo ""
}

cmd_disable() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: Must run as root (sudo magichat desktop disable)${NC}"
        exit 1
    fi

    if [[ ! -f "${DESKTOP_MARKER}" ]]; then
        echo "Desktop is not enabled."
        cmd_status
        return
    fi

    echo ""
    echo "  This will switch back to headless server mode."
    echo "  Desktop packages will remain installed but the display"
    echo "  manager will be disabled."
    echo ""
    read -p "  Continue? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0

    # Switch to multi-user (headless) target
    systemctl set-default multi-user.target

    # Stop and disable display manager
    systemctl stop gdm 2>/dev/null || true
    systemctl disable gdm 2>/dev/null || true

    # Remove marker
    rm -f "${DESKTOP_MARKER}"

    echo ""
    echo -e "  ${GREEN}Switched to headless server mode.${NC}"
    echo "  Desktop packages are still installed — run again to re-enable."
    echo "  To fully remove desktop packages: sudo dnf group remove 'Workstation'"
    echo ""
}

cmd_purge() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: Must run as root${NC}"
        exit 1
    fi

    echo ""
    echo -e "  ${YELLOW}This will REMOVE all desktop packages (~5-7 GB freed).${NC}"
    echo "  Server services are unaffected."
    echo ""
    read -p "  Are you sure? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0

    # Disable desktop first
    systemctl set-default multi-user.target
    systemctl stop gdm 2>/dev/null || true
    systemctl disable gdm 2>/dev/null || true

    # Remove desktop packages
    dnf group remove -y "Workstation" 2>/dev/null || true
    dnf remove -y gdm gnome-shell gnome-session firefox chromium \
        gimp inkscape blender thunderbird 2>/dev/null || true

    # Clean up
    dnf autoremove -y

    # Remove marker and desktop files
    rm -f "${DESKTOP_MARKER}"
    rm -f /usr/share/applications/familiar-dashboard.desktop
    rm -f /usr/share/applications/magichat-terminal.desktop
    rm -f /etc/firefox/policies/policies.json

    echo ""
    echo -e "  ${GREEN}Desktop packages removed.${NC} Back to pure server mode."
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
case "${1:-status}" in
    enable)   cmd_enable ;;
    disable)  cmd_disable ;;
    purge)    cmd_purge ;;
    status)   cmd_status ;;
    *)
        echo "Usage: magichat desktop <enable|disable|purge|status>"
        echo ""
        echo "  enable    Install GNOME desktop + apps (~2-3 GB download)"
        echo "  disable   Switch to headless mode (keeps packages)"
        echo "  purge     Remove all desktop packages (~5-7 GB freed)"
        echo "  status    Show current mode"
        ;;
esac
