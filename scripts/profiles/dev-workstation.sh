#!/usr/bin/env bash
# Magic Hat — Dev Workstation Profile (Sprint 5 full implementation)
# Installs: VSCodium, podman-compose, buildah, skopeo, git-lfs,
# Python/Node/Go system packages; ~/.bashrc.d/ profile with dev defaults.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [dev-workstation] Installing developer stack…"

# ── System packages ───────────────────────────────────────────────────────────
dnf install -y \
    git git-lfs \
    make cmake ninja-build \
    gcc gcc-c++ \
    python3 python3-pip python3-venv python3-devel \
    nodejs npm \
    golang \
    podman-compose \
    buildah \
    skopeo \
    jq \
    httpie \
    tmux \
    2>/dev/null || echo "  WARNING: Some dev packages unavailable"

# ── Rust via rustup (user-level, so it goes to /etc/skel) ────────────────────
# We install the rustup binary system-wide; users get toolchains on first use
if ! command -v rustup &>/dev/null; then
    echo "  [dev-workstation] Fetching rustup installer…"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        -o /tmp/rustup-init.sh 2>/dev/null && \
    chmod +x /tmp/rustup-init.sh && \
    # Install once for the magichat/root user so the binary lands in PATH
    CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup \
        /tmp/rustup-init.sh -y --no-modify-path --profile minimal 2>/dev/null && \
    ln -sf /usr/local/cargo/bin/rustup /usr/local/bin/rustup && \
    ln -sf /usr/local/cargo/bin/cargo  /usr/local/bin/cargo  && \
    ln -sf /usr/local/cargo/bin/rustc  /usr/local/bin/rustc  || \
    echo "  WARNING: Rust install failed — skipping"
fi

# ── VSCodium (Flatpak — open-source VS Code without telemetry) ───────────────
if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists --system flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

    echo "  [dev-workstation] Installing VSCodium…"
    flatpak install --noninteractive --system flathub com.vscodium.codium 2>/dev/null || \
        echo "  WARNING: VSCodium Flatpak install failed — continuing"
fi

# ── Podman Desktop (optional GUI for containers) ─────────────────────────────
# Only install if there's a graphical session available
if command -v flatpak &>/dev/null; then
    flatpak install --noninteractive --system flathub \
        io.podman_desktop.PodmanDesktop 2>/dev/null || true
fi

# ── VSCodium settings (skel) ──────────────────────────────────────────────────
mkdir -p /etc/skel/.var/app/com.vscodium.codium/config/VSCodium/User
cat > /etc/skel/.var/app/com.vscodium.codium/config/VSCodium/User/settings.json << 'VSCODE'
{
  "workbench.colorTheme": "Default Dark Modern",
  "editor.fontFamily": "JetBrains Mono, 'Courier New', monospace",
  "editor.fontSize": 13,
  "editor.lineHeight": 1.6,
  "editor.tabSize": 4,
  "editor.detectIndentation": true,
  "editor.formatOnSave": true,
  "editor.minimap.enabled": false,
  "editor.suggestSelection": "first",
  "terminal.integrated.fontFamily": "JetBrains Mono",
  "terminal.integrated.fontSize": 13,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "git.autofetch": true,
  "git.confirmSync": false,
  "telemetry.telemetryLevel": "off",
  "update.mode": "none"
}
VSCODE

# ── ~/.bashrc.d/magichat-dev.sh (skel) ───────────────────────────────────────
mkdir -p /etc/skel/.bashrc.d
cat > /etc/skel/.bashrc.d/magichat-dev.sh << 'DEVRC'
# Magic Hat — Dev Workstation environment
# Sourced automatically from ~/.bashrc (appended below)

# Prefer VSCodium as default editor
if command -v flatpak &>/dev/null && flatpak info com.vscodium.codium &>/dev/null; then
    export EDITOR="flatpak run com.vscodium.codium --wait"
    export VISUAL="${EDITOR}"
    alias codium='flatpak run com.vscodium.codium'
fi

# Podman socket (Docker-compatible)
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"

# Go workspace
export GOPATH="${HOME}/go"
export PATH="${PATH}:${GOPATH}/bin"

# Cargo/Rust (if system-wide rustup was installed)
[[ -d /usr/local/cargo/bin ]] && export PATH="${PATH}:/usr/local/cargo/bin"

# Git helpers
alias gs='git status'
alias gl='git log --oneline --graph --decorate -20'
alias gd='git diff'

# Familiar AI dev shortcut
alias familiar-dev='curl -s http://localhost:5000/api/status | python3 -m json.tool'
DEVRC

# Ensure ~/.bashrc sources ~/.bashrc.d/ for new users
BASHRC_SKEL="/etc/skel/.bashrc"
if ! grep -q "bashrc.d" "${BASHRC_SKEL}" 2>/dev/null; then
    cat >> "${BASHRC_SKEL}" << 'BASHRC_APPEND'

# Source Magic Hat environment fragments
for f in ~/.bashrc.d/*.sh; do
    [[ -r "$f" ]] && source "$f"
done
unset f
BASHRC_APPEND
fi

# ── Enable podman socket for new users (skel systemd user service) ────────────
mkdir -p /etc/skel/.config/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/podman.socket \
    /etc/skel/.config/systemd/user/default.target.wants/podman.socket 2>/dev/null || true

# ── Gitea desired service ─────────────────────────────────────────────────────
mkdir -p /etc/magichat
grep -q "gitea" /etc/magichat/desired-services.conf 2>/dev/null || \
    echo "gitea" >> /etc/magichat/desired-services.conf

# ── Desktop shortcuts ─────────────────────────────────────────────────────────
SKEL_DESKTOP="/etc/skel/Desktop"
mkdir -p "${SKEL_DESKTOP}"

cat > "${SKEL_DESKTOP}/VSCodium.desktop" << 'VSCODEDESK'
[Desktop Entry]
Type=Application
Name=VSCodium
Comment=Free/Libre Open Source Software Binaries of VS Code
Exec=flatpak run com.vscodium.codium %F
Icon=com.vscodium.codium
Categories=Development;TextEditor;
MimeType=text/plain;inode/directory;
VSCODEDESK

cat > "${SKEL_DESKTOP}/Gitea.desktop" << 'GITEA'
[Desktop Entry]
Type=Link
Name=Gitea (Self-hosted Git)
URL=http://localhost:3000
Icon=internet-web-browser
Categories=Development;
GITEA

echo "  [dev-workstation] Done"
