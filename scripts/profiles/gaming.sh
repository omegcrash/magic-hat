#!/usr/bin/env bash
# Magic Hat — Gaming Profile (Sprint 4 full implementation)
# Installs: RPM Fusion repos → Steam (native RPM), gamemode, gamescope,
# MangoHud, 32-bit Mesa for Proton. Adds user to gamemode group.
#
# Design: RPM over Flatpak for gaming. Steam manages its own Proton sandbox;
# native RPM gives deeper integration (gamemode, gamescope, udev rules).
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [gaming] Installing gaming stack via RPM Fusion…"

# ── RPM Fusion (required for Steam + codecs) ──────────────────────────────────
FEDORA_VER=$(rpm -E '%fedora' 2>/dev/null || echo "41")
echo "  [gaming] Enabling RPM Fusion for Fedora ${FEDORA_VER}…"

dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
    2>/dev/null || \
    echo "  WARNING: RPM Fusion install failed — some gaming packages may be unavailable"

dnf makecache --refresh 2>/dev/null || true

# ── Core gaming packages ──────────────────────────────────────────────────────
dnf install -y \
    steam \
    gamemode \
    gamescope \
    2>/dev/null || echo "  WARNING: Some gaming packages unavailable"

# ── 32-bit Mesa (required for Steam/Proton) ───────────────────────────────────
echo "  [gaming] Installing 32-bit Mesa for Proton compatibility…"
dnf install -y \
    mesa-dri-drivers.i686 \
    mesa-libGL.i686 \
    mesa-vulkan-drivers \
    mesa-vulkan-drivers.i686 \
    vulkan-tools \
    libva \
    libva-intel-driver \
    libva-utils \
    2>/dev/null || echo "  WARNING: Some 32-bit Mesa packages unavailable"

# ── MangoHud (performance overlay) ───────────────────────────────────────────
dnf install -y mangohud mangohud.i686 2>/dev/null || \
    # Fall back to Flatpak extension if RPM not available
    flatpak install --noninteractive --system flathub \
        "org.freedesktop.Platform.VulkanLayer.MangoHud//24.08" 2>/dev/null || true

# ── GPU driver detection ───────────────────────────────────────────────────────
if command -v magichat &>/dev/null; then
    echo "  [gaming] Running GPU detection…"
    magichat gpu --install 2>/dev/null || true
fi

# ── Add users in wheel group to gamemode group ───────────────────────────────
# (Run for all wheel users; also applied at login via PAM in /etc/skel setup)
getent group gamemode &>/dev/null || groupadd -r gamemode
for USER in $(getent group wheel | cut -d: -f4 | tr ',' ' '); do
    usermod -aG gamemode "${USER}" 2>/dev/null || true
done

# ── /etc/gamemode.ini — CPU/GPU performance config for KDE ───────────────────
cat > /etc/gamemode.ini << 'GAMEMODE'
[general]
; Renice game processes — lower = higher CPU priority
renice=10

; Enable GameScope integration
softrealtime=auto

; Run these commands on game start/end
desiredgov=performance

[filter]
; Allow these processes to use gamemode
whitelist=steam
whitelist=proton
whitelist=wine
whitelist=lutris

[gpu]
; NVIDIA: set to max performance mode
nv_powermizer_mode=1

; AMD: apply performance profile via amdgpu sysfs
amd_performance_level=high

[cpu]
; Park no CPUs — use all cores during gaming
park_cores=no

[custom]
; KDE-safe: don't kill compositor, just reduce priority
script_start=/usr/bin/kglobalaccel6 --stop-daemon 2>/dev/null; true
script_end=/usr/bin/kglobalaccel6 2>/dev/null; true
GAMEMODE

chmod 644 /etc/gamemode.ini

# ── vm.max_map_count (isolated from base CIS hardening) ───────────────────────
# Required for many modern games (256 → 2147483642).
# Written to its own file so security/sysctl-hardening.conf is untouched.
cat > /etc/sysctl.d/99-magichat-gaming.conf << 'SYSCTL'
# Magic Hat Gaming Profile — vm.max_map_count override
# Required by: Cities: Skylines, Star Citizen, Elden Ring, most Unity games.
# Isolated in its own sysctl.d file to keep CIS hardening rules separate.
vm.max_map_count = 2147483642
SYSCTL

sysctl --system 2>/dev/null || true

# ── Desktop shortcut for Steam ────────────────────────────────────────────────
SKEL_DESKTOP="/etc/skel/Desktop"
mkdir -p "${SKEL_DESKTOP}"

cat > "${SKEL_DESKTOP}/Steam.desktop" << 'STEAM'
[Desktop Entry]
Type=Application
Name=Steam
Exec=steam %U
Icon=steam
Categories=Game;Network;
StartupNotify=false
STEAM

# ── MangoHud system config (skel) ────────────────────────────────────────────
mkdir -p /etc/skel/.config/MangoHud
cat > /etc/skel/.config/MangoHud/MangoHud.conf << 'MANGOHUD'
legacy_layout=false
horizontal
background_alpha=0.4
font_size=20
fps
frametime=1
gpu_stats
cpu_stats
ram
vram
throttling_status
MANGOHUD

echo "  [gaming] Done — Steam and gamemode installed"
echo "  [gaming] NOTE: Log out and back in for gamemode group membership to take effect"
