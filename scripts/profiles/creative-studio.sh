#!/usr/bin/env bash
# Magic Hat — Creative Studio Profile
# Installs: GIMP, Krita, Inkscape, Blender, Kdenlive, Jellyfin
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [creative-studio] Installing creative tools…"

# ── Flatpak apps ──────────────────────────────────────────────────────────────
FLATPAKS=(
    org.gimp.GIMP
    org.kde.krita
    org.inkscape.Inkscape
    org.blender.Blender
    org.kde.kdenlive
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

# ── Jellyfin (media server for Artist job class) ───────────────────────────────
if command -v podman &>/dev/null || command -v docker &>/dev/null; then
    echo "  [creative-studio] Jellyfin media server will be available via Familiar dashboard → Services"
    # Actual provisioning is handled by Familiar ServiceManager (familiar-agent)
    # This just records the intent in Magic Hat config
    mkdir -p /etc/magichat
    echo "jellyfin" >> /etc/magichat/desired-services.conf
fi

# ── Font packages for design work ─────────────────────────────────────────────
dnf install -y \
    google-noto-fonts-all \
    adobe-source-sans-fonts \
    adobe-source-serif-fonts \
    adobe-source-code-pro-fonts \
    2>/dev/null || true

# ── Desktop shortcuts ─────────────────────────────────────────────────────────
SKEL_DESKTOP="/etc/skel/Desktop"
mkdir -p "${SKEL_DESKTOP}"

for APP in GIMP Krita Inkscape Blender Kdenlive; do
    APP_LOWER=$(echo "${APP}" | tr '[:upper:]' '[:lower:]')
    cat > "${SKEL_DESKTOP}/${APP}.desktop" << EOF
[Desktop Entry]
Type=Application
Name=${APP}
Exec=flatpak run $(grep -r "${APP_LOWER}" /home/mel/Desktop/magic-hat/scripts/profiles/profile-meta.json 2>/dev/null | grep -o 'org\.[^ ]*' | head -1 || echo "org.gimp.GIMP")
Icon=${APP_LOWER}
Categories=Graphics;
EOF
done

echo "  [creative-studio] Done"
