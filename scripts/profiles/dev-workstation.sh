#!/usr/bin/env bash
# Magic Hat — Dev Workstation Profile
# Installs: VS Code, Podman Desktop, Gitea, Python/Node/Go/Rust toolchains
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [dev-workstation] Installing developer stack…"

# ── System packages ───────────────────────────────────────────────────────────
dnf install -y \
    git git-lfs \
    make cmake \
    gcc gcc-c++ \
    python3 python3-pip python3-venv \
    nodejs npm \
    golang \
    2>/dev/null || echo "  WARNING: Some dev packages unavailable"

# ── Rust via rustup ───────────────────────────────────────────────────────────
if ! command -v rustc &>/dev/null; then
    echo "  [dev-workstation] Installing Rust toolchain…"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --no-modify-path --profile minimal 2>/dev/null || \
        echo "  WARNING: Rust install failed — skipping"
fi

# ── Flatpak apps ──────────────────────────────────────────────────────────────
FLATPAKS=(
    com.visualstudio.code
    io.podman_desktop.PodmanDesktop
)

if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    for APP in "${FLATPAKS[@]}"; do
        echo "    Installing Flatpak: ${APP}"
        flatpak install -y flathub "${APP}" 2>/dev/null || \
            echo "    WARNING: ${APP} install failed — continuing"
    done
fi

# ── Gitea (self-hosted Git) ────────────────────────────────────────────────────
mkdir -p /etc/magichat
echo "gitea" >> /etc/magichat/desired-services.conf

# ── VS Code settings (skel) ───────────────────────────────────────────────────
mkdir -p /etc/skel/.config/Code/User
cat > /etc/skel/.config/Code/User/settings.json << 'VSCODE'
{
  "workbench.colorTheme": "Default Dark+",
  "editor.fontFamily": "JetBrains Mono, 'Courier New', monospace",
  "editor.fontSize": 13,
  "editor.lineHeight": 1.6,
  "editor.tabSize": 4,
  "editor.formatOnSave": true,
  "terminal.integrated.fontFamily": "JetBrains Mono",
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "git.autofetch": true
}
VSCODE

# ── Desktop shortcuts ─────────────────────────────────────────────────────────
SKEL_DESKTOP="/etc/skel/Desktop"
mkdir -p "${SKEL_DESKTOP}"

cat > "${SKEL_DESKTOP}/VS Code.desktop" << 'VSCODEDESK'
[Desktop Entry]
Type=Application
Name=Visual Studio Code
Exec=flatpak run com.visualstudio.code
Icon=com.visualstudio.code
Categories=Development;TextEditor;
VSCODEDESK

echo "  [dev-workstation] Done"
