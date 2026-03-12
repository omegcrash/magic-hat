#!/usr/bin/env bash
# Magic Hat — Theme Installation Script
# Copies all Magic Hat theme components to their system-wide locations.
# Called by kde-configure.sh during kickstart %post, and available
# as a standalone command for manual re-application:
#
#   sudo /opt/magichat/scripts/install-themes.sh
#
# Safe to re-run.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

THEME_SRC="${1:-/opt/magichat/themes}"

echo "=== Magic Hat Theme Installer: $(date) ==="

# ── KDE Color Scheme ──────────────────────────────────────────────────────────
COLORSCHEME_DST="/usr/share/color-schemes"
mkdir -p "${COLORSCHEME_DST}"
if [[ -f "${THEME_SRC}/colors/MagicHat.colors" ]]; then
    cp "${THEME_SRC}/colors/MagicHat.colors" "${COLORSCHEME_DST}/MagicHat.colors"
    echo "  Color scheme: installed → ${COLORSCHEME_DST}/MagicHat.colors"
fi

# Apply system-wide via kwriteconfig6
kwriteconfig6 --file /etc/xdg/kdeglobals \
    --group General --key ColorScheme MagicHat 2>/dev/null || true

# ── KDE Plasma Look-and-Feel package ─────────────────────────────────────────
LAF_SRC="${THEME_SRC}/plasma/look-and-feel/com.magichat.desktop"
if [[ -d "${LAF_SRC}" ]]; then
    if command -v kpackagetool6 &>/dev/null; then
        # Try upgrade first, then fresh install
        kpackagetool6 --global --upgrade "${LAF_SRC}" \
            --type Plasma/LookAndFeel 2>/dev/null || \
        kpackagetool6 --global --install "${LAF_SRC}" \
            --type Plasma/LookAndFeel 2>/dev/null || true
        echo "  Look-and-feel: installed via kpackagetool6"
    else
        # Manual copy fallback
        LAF_DST="/usr/share/plasma/look-and-feel/com.magichat.desktop"
        mkdir -p "${LAF_DST}"
        cp -r "${LAF_SRC}/." "${LAF_DST}/"
        echo "  Look-and-feel: copied manually → ${LAF_DST}"
    fi
    kwriteconfig6 --file /etc/xdg/kdeglobals \
        --group KDE --key LookAndFeelPackage com.magichat.desktop 2>/dev/null || true
fi

# ── KDE Plasma Splash Screen ─────────────────────────────────────────────────
SPLASH_SRC="${THEME_SRC}/plasma/splash/com.magichat.desktop"
if [[ -d "${SPLASH_SRC}" ]]; then
    SPLASH_DST="/usr/share/plasma/look-and-feel/com.magichat.desktop"
    # Plasma 6: splash is part of the look-and-feel package, no separate install
    # Just ensure contents/splash/ is in the look-and-feel directory
    SPLASH_TARGET="${SPLASH_DST}/contents/splash"
    mkdir -p "${SPLASH_TARGET}"
    if [[ -f "${SPLASH_SRC}/contents/splash/Splash.qml" ]]; then
        cp "${SPLASH_SRC}/contents/splash/Splash.qml" "${SPLASH_TARGET}/Splash.qml"
        echo "  Splash screen: installed → ${SPLASH_TARGET}/Splash.qml"
    fi
    kwriteconfig6 --file /etc/xdg/ksplashrc \
        --group KSplash --key Theme com.magichat.desktop 2>/dev/null || true
fi

# ── SDDM Login Theme ──────────────────────────────────────────────────────────
SDDM_SRC="${THEME_SRC}/sddm/magichat"
SDDM_DST="/usr/share/sddm/themes/magichat"
if [[ -d "${SDDM_SRC}" ]]; then
    mkdir -p "/usr/share/sddm/themes"
    cp -r "${SDDM_SRC}" "/usr/share/sddm/themes/"
    echo "  SDDM theme: installed → ${SDDM_DST}"

    # Write SDDM config
    mkdir -p /etc/sddm.conf.d
    cat > /etc/sddm.conf.d/10-magichat-theme.conf << 'SDDMCONF'
[Theme]
Current=magichat
CursorTheme=breeze_cursors
Font=Noto Sans,10,-1,5,50,0,0,0,0,0
SDDMCONF
    echo "  SDDM config: written → /etc/sddm.conf.d/10-magichat-theme.conf"
fi

# ── Desktop Wallpaper ─────────────────────────────────────────────────────────
WALLPAPER_SRC="${THEME_SRC}/wallpaper/magichat-dark.svg"
WALLPAPER_DST="/usr/share/wallpapers/MagicHat"
if [[ -f "${WALLPAPER_SRC}" ]]; then
    mkdir -p "${WALLPAPER_DST}/contents/images"
    cp "${WALLPAPER_SRC}" "${WALLPAPER_DST}/contents/images/magichat-dark.svg"
    # Metadata for KDE wallpaper chooser
    cat > "${WALLPAPER_DST}/metadata.json" << 'WALLMETA'
{
    "KPlugin": {
        "Authors": [{ "Name": "George Scott Foley" }],
        "Category": "Wallpaper",
        "Description": "Magic Hat — dark desktop wallpaper",
        "Id": "com.magichat.wallpaper.dark",
        "License": "MIT",
        "Name": "Magic Hat Dark"
    }
}
WALLMETA
    echo "  Wallpaper: installed → ${WALLPAPER_DST}"

    # Set as default for new users via plasma config
    mkdir -p /etc/skel/.config
    kwriteconfig6 \
        --file /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc \
        --group Containments --group 2 \
        --group Wallpaper --group org.kde.image \
        --group General --key Image \
        "file://${WALLPAPER_DST}/contents/images/magichat-dark.svg" 2>/dev/null || true
fi

# ── Konsole Color Scheme ──────────────────────────────────────────────────────
KONSOLE_SRC="${THEME_SRC}/konsole/MagicHat.colorscheme"
KONSOLE_DST="/usr/share/konsole"
if [[ -f "${KONSOLE_SRC}" ]]; then
    mkdir -p "${KONSOLE_DST}"
    cp "${KONSOLE_SRC}" "${KONSOLE_DST}/MagicHat.colorscheme"
    echo "  Konsole scheme: installed → ${KONSOLE_DST}/MagicHat.colorscheme"
fi

# ── Set Konsole defaults in skel ──────────────────────────────────────────────
mkdir -p /etc/skel/.local/share/konsole
cat > /etc/skel/.local/share/konsole/MagicHat.profile << 'KONSOLEPROFILE'
[Appearance]
ColorScheme=MagicHat
Font=JetBrains Mono,11,-1,5,50,0,0,0,0,0

[General]
Name=Magic Hat
Parent=FALLBACK/

[Scrolling]
ScrollBarPosition=2

[Terminal Features]
BidiRenderingEnabled=false
BlinkingCursorEnabled=true
KONSOLEPROFILE

# Set as default Konsole profile
mkdir -p /etc/skel/.config
cat > /etc/skel/.config/konsolerc << 'KONSOLERC'
[Desktop Entry]
DefaultProfile=MagicHat.profile

[General]
ConfigVersion=1
KONSOLERC

echo "  Konsole: default profile set → MagicHat"

# ── Rebuild system cache ──────────────────────────────────────────────────────
kbuildsycoca6 --noincremental 2>/dev/null || \
    kbuildsycoca5 --noincremental 2>/dev/null || true

echo "=== Theme installation complete ==="
