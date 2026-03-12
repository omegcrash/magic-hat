#!/usr/bin/env bash
# Magic Hat — Gaming Profile
# Installs: Steam (Flatpak), Lutris, MangoHud, 32-bit Mesa, GPU drivers
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [gaming] Installing gaming stack…"

# ── 32-bit Mesa (required for Steam/Proton) ───────────────────────────────────
echo "  [gaming] Enabling 32-bit Mesa for Proton compatibility…"
dnf install -y \
    mesa-dri-drivers.i686 \
    mesa-libGL.i686 \
    mesa-vulkan-drivers \
    mesa-vulkan-drivers.i686 \
    vulkan-tools \
    2>/dev/null || echo "  WARNING: Some 32-bit Mesa packages unavailable"

# ── GPU driver detection ───────────────────────────────────────────────────────
if command -v magichat &>/dev/null; then
    echo "  [gaming] Running GPU detection…"
    magichat gpu --install 2>/dev/null || true
fi

# ── Flatpak apps ──────────────────────────────────────────────────────────────
FLATPAKS=(
    com.valvesoftware.Steam
    net.lutris.Lutris
    "org.freedesktop.Platform.VulkanLayer.MangoHud//23.08"
)

if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    for APP in "${FLATPAKS[@]}"; do
        echo "    Installing Flatpak: ${APP}"
        flatpak install -y flathub "${APP}" 2>/dev/null || \
            echo "    WARNING: ${APP} install failed — continuing"
    done
else
    echo "  WARNING: flatpak not found — skipping Flatpak apps"
fi

# ── MangoHud system config ────────────────────────────────────────────────────
mkdir -p /etc/skel/.config/MangoHud
cat > /etc/skel/.config/MangoHud/MangoHud.conf << 'MANGOHUD'
legacy_layout=false
horizontal
background_alpha=0.4
font_size=20
fps
frametime
gpu_stats
cpu_stats
ram
vram
MANGOHUD

# ── Steam desktop shortcut ────────────────────────────────────────────────────
SKEL_DESKTOP="/etc/skel/Desktop"
mkdir -p "${SKEL_DESKTOP}"
cat > "${SKEL_DESKTOP}/Steam.desktop" << 'STEAM'
[Desktop Entry]
Type=Application
Name=Steam
Exec=flatpak run com.valvesoftware.Steam
Icon=steam
Categories=Game;
STEAM

echo "  [gaming] Done"
