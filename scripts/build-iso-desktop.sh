#!/usr/bin/env bash
# Magic Hat Desktop — ISO Build Script
# Builds a bootable Magic Hat Desktop ISO (KDE Plasma) from the Kickstart file.
#
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Usage: sudo ./scripts/build-iso-desktop.sh [--version 0.4.0]
#
# Requires on Fedora host:
#   dnf install lorax mkksiso curl coreutils

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
VERSION="0.4.0"
VARIANT="desktop"
BUILD_DIR="/tmp/magichat-desktop-build"
RESULT_DIR="${PROJECT_DIR}/dist"
ISO_NAME="magichat-${VARIANT}-${VERSION}-x86_64.iso"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --variant) VARIANT="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done
ISO_NAME="magichat-${VARIANT}-${VERSION}-x86_64.iso"

echo "============================================="
echo "  Magic Hat Desktop ISO Builder v${VERSION}"
echo "============================================="
echo ""

# Preflight
if [[ $EUID -ne 0 ]]; then
    echo "Error: Must run as root (sudo)."
    exit 1
fi

for cmd in lorax mkksiso; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' not found. Install with: dnf install lorax"
        exit 1
    fi
done

# Clean previous builds
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${RESULT_DIR}"

echo "[1/4] Preparing Magic Hat Desktop overlay..."

OVERLAY="${BUILD_DIR}/overlay"
mkdir -p "${OVERLAY}/opt/magichat"/{scripts,scripts/profiles,systemd,nginx,firewall,firstboot,firstboot/desktop-wizard/pages,security,security/polkit,lib,themes}

# First-boot markers
touch "${OVERLAY}/opt/magichat/.needs-firstboot"
mkdir -p "${OVERLAY}/opt/magichat/firewall/filter.d"
mkdir -p "${OVERLAY}/etc/magichat"
touch "${OVERLAY}/etc/magichat/desktop.mode"
touch "${OVERLAY}/etc/magichat/profile.unset"

# Scripts
for f in backup.sh magichat detect-gpu.sh magichat-model-check \
          provider-health.sh configure-providers.sh kde-configure.sh \
          familiar-briefing.sh; do
    [[ -f "${PROJECT_DIR}/scripts/${f}" ]] && \
        cp "${PROJECT_DIR}/scripts/${f}" "${OVERLAY}/opt/magichat/scripts/"
done
# Profile scripts
if [[ -d "${PROJECT_DIR}/scripts/profiles" ]]; then
    cp -r "${PROJECT_DIR}/scripts/profiles/." \
          "${OVERLAY}/opt/magichat/scripts/profiles/"
fi
chmod +x "${OVERLAY}/opt/magichat/scripts/"* 2>/dev/null || true

# Systemd units
cp "${PROJECT_DIR}/systemd/"* "${OVERLAY}/opt/magichat/systemd/" 2>/dev/null || true

# Nginx
cp "${PROJECT_DIR}/nginx/"* "${OVERLAY}/opt/magichat/nginx/" 2>/dev/null || true

# Firewall
[[ -f "${PROJECT_DIR}/firewall/magichat.xml" ]] && \
    cp "${PROJECT_DIR}/firewall/magichat.xml" "${OVERLAY}/opt/magichat/firewall/"
[[ -f "${PROJECT_DIR}/firewall/jail.local" ]] && \
    cp "${PROJECT_DIR}/firewall/jail.local" "${OVERLAY}/opt/magichat/firewall/"
[[ -d "${PROJECT_DIR}/firewall/filter.d" ]] && \
    cp "${PROJECT_DIR}/firewall/filter.d/"* \
       "${OVERLAY}/opt/magichat/firewall/filter.d/" 2>/dev/null || true

# Security
cp "${PROJECT_DIR}/security/"*.conf \
   "${PROJECT_DIR}/security/"*.json \
   "${PROJECT_DIR}/security/"*.rules 2>/dev/null \
   "${OVERLAY}/opt/magichat/security/" 2>/dev/null || true
[[ -d "${PROJECT_DIR}/security/polkit" ]] && \
    cp "${PROJECT_DIR}/security/polkit/"* \
       "${OVERLAY}/opt/magichat/security/polkit/" 2>/dev/null || true

# Lib (familiar_bridge.py etc.)
cp "${PROJECT_DIR}/lib/"*.py "${OVERLAY}/opt/magichat/lib/" 2>/dev/null || true

# Firstboot wizard
cp -r "${PROJECT_DIR}/firstboot/." "${OVERLAY}/opt/magichat/firstboot/"

# Themes (SDDM, KDE look-and-feel, colors, icons)
if [[ -d "${PROJECT_DIR}/themes" ]]; then
    cp -r "${PROJECT_DIR}/themes/." "${OVERLAY}/opt/magichat/themes/"
fi

# Plasma applet
if [[ -d "${PROJECT_DIR}/plasma-applet" ]]; then
    cp -r "${PROJECT_DIR}/plasma-applet" "${OVERLAY}/opt/magichat/"
fi

echo "[2/4] Downloading Fedora netinstall ISO..."

FEDORA_VERSION="41"
FEDORA_ISO_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/${FEDORA_VERSION}/Server/x86_64/iso/Fedora-Server-netinst-x86_64-${FEDORA_VERSION}-1.4.iso"
FEDORA_ISO="${BUILD_DIR}/fedora-netinst.iso"

if [[ ! -f "${FEDORA_ISO}" ]]; then
    echo "  Downloading Fedora ${FEDORA_VERSION} netinstall (~800MB)..."
    curl -L --progress-bar -o "${FEDORA_ISO}" "${FEDORA_ISO_URL}"
else
    echo "  Using cached Fedora netinstall."
fi

echo "[3/4] Building Magic Hat Desktop ISO..."

mkksiso \
    --ks "${PROJECT_DIR}/kickstart/magichat-desktop.ks" \
    --add "${OVERLAY}" \
    "${FEDORA_ISO}" \
    "${RESULT_DIR}/${ISO_NAME}"

echo "[4/4] Generating checksums..."
cd "${RESULT_DIR}"
sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"

echo ""
echo "============================================="
echo "  Build complete!"
echo "============================================="
echo ""
echo "  ISO:     ${RESULT_DIR}/${ISO_NAME}"
echo "  SHA256:  ${RESULT_DIR}/${ISO_NAME}.sha256"
echo "  Size:    $(du -h "${RESULT_DIR}/${ISO_NAME}" | cut -f1)"
echo ""
echo "  Profiles available on first boot:"
echo "    ✓ AI Companion  (always on)"
echo "    ✓ Privacy Suite (always on)"
echo "    ○ Creative Studio (Krita, Inkscape, Kdenlive, Blender)"
echo "    ○ Gaming (Steam + Mesa/Vulkan)"
echo "    ○ Dev Workstation (VSCodium, Podman, Gitea)"
echo ""
