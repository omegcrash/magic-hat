#!/usr/bin/env bash
# Magic Hat — Creative Studio Profile (Sprint 4 full implementation)
# Installs: Krita, Inkscape, Blender, Kdenlive, Darktable
# Sets MIME associations so files open in the right app.
# Pre-pins Krita to the KDE application launcher.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [creative-studio] Installing creative tools…"

# ── Flatpak apps ──────────────────────────────────────────────────────────────
FLATPAKS=(
    org.kde.krita            # Raster painting + digital art
    org.inkscape.Inkscape    # Vector graphics / SVG
    org.blender.Blender      # 3D modelling, sculpting, animation
    org.kde.kdenlive         # Video editing
    org.darktable.Darktable  # RAW photo processing / digital darkroom
)

if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists --system flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

    for APP in "${FLATPAKS[@]}"; do
        echo "    Installing Flatpak: ${APP}"
        flatpak install --noninteractive --system flathub "${APP}" 2>/dev/null || \
            echo "    WARNING: ${APP} install failed — continuing"
    done
else
    echo "  WARNING: flatpak not found — skipping Flatpak apps"
fi

# ── Font packages for design work ─────────────────────────────────────────────
dnf install -y \
    google-noto-fonts-all \
    adobe-source-sans-fonts \
    adobe-source-serif-fonts \
    adobe-source-code-pro-fonts \
    2>/dev/null || true

# ── MIME associations ─────────────────────────────────────────────────────────
# Written to /etc/skel so every new user gets them on first login.
MIMEAPPS_DIR="/etc/skel/.config"
mkdir -p "${MIMEAPPS_DIR}"

cat > "${MIMEAPPS_DIR}/mimeapps.list" << 'MIMEAPPS'
[Default Applications]
# Krita — raster art
image/x-krita=org.kde.krita.desktop
image/png=org.kde.krita.desktop
image/jpeg=org.kde.krita.desktop
image/tiff=org.kde.krita.desktop
image/x-tga=org.kde.krita.desktop
image/x-xcf=org.kde.krita.desktop

# Inkscape — vector / SVG
image/svg+xml=org.inkscape.Inkscape.desktop
image/svg+xml-compressed=org.inkscape.Inkscape.desktop

# Darktable — RAW formats
image/x-canon-cr2=org.darktable.Darktable.desktop
image/x-canon-cr3=org.darktable.Darktable.desktop
image/x-nikon-nef=org.darktable.Darktable.desktop
image/x-olympus-orf=org.darktable.Darktable.desktop
image/x-sony-arw=org.darktable.Darktable.desktop
image/x-fuji-raf=org.darktable.Darktable.desktop
image/x-panasonic-rw2=org.darktable.Darktable.desktop
image/x-adobe-dng=org.darktable.Darktable.desktop
image/x-raw=org.darktable.Darktable.desktop

# Blender — 3D
model/gltf-binary=org.blender.Blender.desktop
model/gltf+json=org.blender.Blender.desktop

# Kdenlive — video
video/mp4=org.kde.kdenlive.desktop
video/x-matroska=org.kde.kdenlive.desktop
video/quicktime=org.kde.kdenlive.desktop
video/x-msvideo=org.kde.kdenlive.desktop
video/webm=org.kde.kdenlive.desktop

[Added Associations]
image/x-krita=org.kde.krita.desktop;
image/svg+xml=org.inkscape.Inkscape.desktop;
MIMEAPPS

# ── Pre-pin Krita to application launcher favourites ─────────────────────────
# Appended to plasma-org.kde.plasma.desktop-appletsrc so it shows in kickoff
KICKOFF_CONF="/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [[ -f "${KICKOFF_CONF}" ]]; then
    # Add Krita to kickoff pinned apps if not already listed
    if ! grep -q "krita" "${KICKOFF_CONF}" 2>/dev/null; then
        sed -i 's/\(launchers=.*\)/\1,applications:org.kde.krita.desktop/' "${KICKOFF_CONF}" 2>/dev/null || true
    fi
fi

# Write standalone kickoff favourites file as fallback
mkdir -p /etc/skel/.local/share/kservices5
cat >> /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc << 'KICKOFF' 2>/dev/null || true

[Containments][1][Applets][2][Configuration][General]
favoriteApps=preferred://filemanager,org.kde.krita.desktop,org.inkscape.Inkscape.desktop,org.blender.Blender.desktop,preferred://browser
KICKOFF

# ── Jellyfin media server (Artist job class) ──────────────────────────────────
mkdir -p /etc/magichat
grep -q "jellyfin" /etc/magichat/desired-services.conf 2>/dev/null || \
    echo "jellyfin" >> /etc/magichat/desired-services.conf

# ── Desktop shortcuts ─────────────────────────────────────────────────────────
SKEL_DESKTOP="/etc/skel/Desktop"
mkdir -p "${SKEL_DESKTOP}"

declare -A APP_IDS=(
    ["Krita"]="org.kde.krita"
    ["Inkscape"]="org.inkscape.Inkscape"
    ["Blender"]="org.blender.Blender"
    ["Kdenlive"]="org.kde.kdenlive"
    ["Darktable"]="org.darktable.Darktable"
)

for NAME in "${!APP_IDS[@]}"; do
    ID="${APP_IDS[$NAME]}"
    cat > "${SKEL_DESKTOP}/${NAME}.desktop" << EOF
[Desktop Entry]
Type=Application
Name=${NAME}
Exec=flatpak run ${ID}
Icon=${ID}
Categories=Graphics;
EOF
done

# ── Activate Artist job class in Familiar when available ─────────────────────
FAMILIAR_CONF_DIR="/etc/magichat"
mkdir -p "${FAMILIAR_CONF_DIR}"
echo "artist" >> "${FAMILIAR_CONF_DIR}/job-class-hint.conf" 2>/dev/null || true

echo "  [creative-studio] Done"
