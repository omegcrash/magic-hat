#!/usr/bin/env bash
# Magic Hat — ISO Build Script
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Builds a bootable Magic Hat ISO from the Kickstart file.
# Requires: Fedora host with lorax, anaconda packages.
#
# Usage: sudo ./scripts/build-iso.sh [--version 0.1.0]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
VERSION="${1:-0.1.0}"
BUILD_DIR="/tmp/magichat-build"
RESULT_DIR="${PROJECT_DIR}/dist"
ISO_NAME="magichat-${VERSION}-x86_64.iso"

echo "========================================="
echo "  Magic Hat ISO Builder v${VERSION}"
echo "========================================="
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

echo "[1/4] Preparing Magic Hat overlay..."
# Create the /opt/magichat tree that the Kickstart expects
OVERLAY="${BUILD_DIR}/overlay"
mkdir -p "${OVERLAY}/opt/magichat"/{scripts,systemd,nginx,firewall,firstboot,security}
mkdir -p "${OVERLAY}/opt/magichat/firewall/filter.d"

cp "${PROJECT_DIR}/scripts/backup.sh" "${OVERLAY}/opt/magichat/scripts/"
cp "${PROJECT_DIR}/scripts/magichat" "${OVERLAY}/opt/magichat/scripts/"
cp "${PROJECT_DIR}/systemd/"* "${OVERLAY}/opt/magichat/systemd/"
cp "${PROJECT_DIR}/nginx/"* "${OVERLAY}/opt/magichat/nginx/"
cp "${PROJECT_DIR}/firewall/magichat.xml" "${OVERLAY}/opt/magichat/firewall/"
cp "${PROJECT_DIR}/firewall/jail.local" "${OVERLAY}/opt/magichat/firewall/"
cp "${PROJECT_DIR}/firewall/filter.d/"* "${OVERLAY}/opt/magichat/firewall/filter.d/"
cp "${PROJECT_DIR}/security/"* "${OVERLAY}/opt/magichat/security/"
chmod +x "${OVERLAY}/opt/magichat/scripts/"*
chmod +x "${OVERLAY}/opt/magichat/security/hardening.sh"

echo "[2/4] Downloading Fedora Server netinstall..."
FEDORA_VERSION="41"
FEDORA_ISO_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/${FEDORA_VERSION}/Server/x86_64/iso/Fedora-Server-netinst-x86_64-${FEDORA_VERSION}-1.4.iso"
FEDORA_ISO="${BUILD_DIR}/fedora-server-netinst.iso"

if [[ ! -f "${FEDORA_ISO}" ]]; then
    curl -L -o "${FEDORA_ISO}" "${FEDORA_ISO_URL}"
fi

echo "[3/4] Building Magic Hat ISO..."
# Embed our Kickstart into the Fedora netinstall ISO
mkksiso \
    --ks "${PROJECT_DIR}/kickstart/magichat.ks" \
    --add "${OVERLAY}" \
    "${FEDORA_ISO}" \
    "${RESULT_DIR}/${ISO_NAME}"

echo "[4/4] Generating checksums..."
cd "${RESULT_DIR}"
sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"

echo ""
echo "========================================="
echo "  Build complete!"
echo "========================================="
echo ""
echo "  ISO: ${RESULT_DIR}/${ISO_NAME}"
echo "  SHA: ${RESULT_DIR}/${ISO_NAME}.sha256"
echo "  Size: $(du -h "${RESULT_DIR}/${ISO_NAME}" | cut -f1)"
echo ""
echo "  Boot this ISO to install Magic Hat."
echo ""
