# Magic Hat Desktop — Fedora KDE Kickstart
# Purpose-built Linux desktop with Familiar AI as a first-class citizen.
# "Windows 98 done right" — consistent, approachable, just works.
#
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Usage:
#   sudo ./scripts/build-iso-desktop.sh [--version 0.4.0]
#   OR boot Fedora netinstall with: inst.ks=https://raw.githubusercontent.com/omegcrash/magic-hat/master/kickstart/magichat-desktop.ks

# ── Base ──────────────────────────────────────────────────────────────────────
graphical
lang en_US.UTF-8
keyboard us
timezone UTC --utc
selinux --enforcing
firewall --enabled --ssh --http --https
rootpw --lock
firstboot --disable
reboot

# ── Storage ───────────────────────────────────────────────────────────────────
autopart --type=lvm --fstype=xfs
zerombr
clearpart --all --initlabel

# ── Network ───────────────────────────────────────────────────────────────────
network --bootproto=dhcp --device=link --activate --hostname=magichat.local

# ── Display Manager ───────────────────────────────────────────────────────────
xconfig --startxonboot

# ── Package Selection ─────────────────────────────────────────────────────────
%packages --excludedocs

# KDE Plasma desktop environment
@^kde-desktop-environment

# KDE core components
plasma-desktop
sddm
kde-settings-plasma
plasma-nm
plasma-pa
plasma-vault
kdeconnect-kde
plasma-browser-integration
plasma-systemmonitor
plasma-disks
plasma-firewall

# KDE applications
konsole
dolphin
kate
ark
spectacle
kinfocenter
kcalc
kcolorchooser
gwenview
okular
elisa
kamoso
kdeutils-common

# Bluetooth
bluedevil
bluez

# Flatpak + portal
flatpak
xdg-desktop-portal-kde
xdg-desktop-portal

# Theme + look and feel
breeze
breeze-icon-theme
kde-filesystem
papirus-icon-theme

# Fonts
google-noto-sans-fonts
google-noto-emoji-fonts
google-noto-fonts-common
liberation-fonts-common
liberation-mono-fonts
liberation-sans-fonts
liberation-serif-fonts
jetbrains-mono-fonts-all

# Firefox browser
firefox

# Core services (needed by Familiar / Reflection)
podman
podman-compose
python3.11
python3.11-pip
python3.11-devel

# System tools
firewalld
dnf-automatic
cronie
rsync
tar
gzip
unzip
p7zip
xz
bzip2
git
git-lfs
jq
htop
nano
vim-enhanced
curl
wget
bind-utils

# Document processing (Familiar skills)
libreoffice-headless
libreoffice-writer
libreoffice-calc
libreoffice-impress
poppler-utils
ImageMagick
ffmpeg
sox
ghostscript
pandoc
tesseract
tesseract-langpack-eng

# Hardware detection
lshw
pciutils
usbutils
smartmontools

# Security
audit
aide
openssh-server
gnupg2
crypto-policies-scripts

# WiFi firmware (desktop needs wireless — intentionally NOT excluded)
# (unlike server kickstart which strips iwl* firmware)

%end

# ── Post-install ──────────────────────────────────────────────────────────────
%post --log=/root/magichat-desktop-install.log

echo "=== Magic Hat Desktop post-install: $(date) ==="

# ── Desktop mode marker ────────────────────────────────────────────────────────
mkdir -p /etc/magichat
touch /etc/magichat/desktop.mode
touch /etc/magichat/profile.unset

# ── Create service user ────────────────────────────────────────────────────────
useradd --system --create-home --shell /bin/bash --comment "Magic Hat service" magichat
usermod -aG wheel magichat
usermod -aG render magichat 2>/dev/null || true
usermod -aG video magichat 2>/dev/null || true

# ── Install Familiar + Reflection ─────────────────────────────────────────────
python3.11 -m pip install --upgrade pip
python3.11 -m pip install "familiar-agent>=1.15.41"
python3.11 -m pip install "reflection-agent[full]>=2.0.54"

# ── Graphical target ──────────────────────────────────────────────────────────
systemctl set-default graphical.target
systemctl enable sddm

# ── SDDM configuration ────────────────────────────────────────────────────────
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/magichat.conf << 'SDDMCONF'
[Theme]
Current=magichat

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[X11]
ServerArguments=-nolisten tcp -dpi 96

[Wayland]
SessionDir=/usr/share/wayland-sessions
SDDMCONF

# ── Install SDDM theme ────────────────────────────────────────────────────────
if [[ -d /opt/magichat/themes/sddm/magichat ]]; then
    cp -r /opt/magichat/themes/sddm/magichat /usr/share/sddm/themes/
fi

# ── Install KDE look-and-feel ─────────────────────────────────────────────────
if [[ -d /opt/magichat/themes/plasma/look-and-feel/com.magichat.desktop ]]; then
    mkdir -p /usr/share/plasma/look-and-feel/
    cp -r /opt/magichat/themes/plasma/look-and-feel/com.magichat.desktop \
          /usr/share/plasma/look-and-feel/
fi

# ── Install color scheme ──────────────────────────────────────────────────────
if [[ -f /opt/magichat/themes/colors/MagicHat.colors ]]; then
    cp /opt/magichat/themes/colors/MagicHat.colors /usr/share/color-schemes/
fi

# ── Install icon ──────────────────────────────────────────────────────────────
if [[ -f /opt/magichat/themes/icons/familiar-icon.png ]]; then
    install -Dm644 /opt/magichat/themes/icons/familiar-icon.png \
        /usr/share/icons/hicolor/256x256/apps/familiar.png
fi

# ── Apply KDE system defaults ─────────────────────────────────────────────────
if [[ -f /opt/magichat/scripts/kde-configure.sh ]]; then
    chmod +x /opt/magichat/scripts/kde-configure.sh
    /opt/magichat/scripts/kde-configure.sh
fi

# ── Flathub remote ────────────────────────────────────────────────────────────
flatpak remote-add --if-not-exists --system flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo || true

# ── Familiar dashboard .desktop shortcut ─────────────────────────────────────
cat > /usr/share/applications/familiar-dashboard.desktop << 'DESKENTRY'
[Desktop Entry]
Name=Familiar Dashboard
Comment=Open the Familiar AI Dashboard
Exec=firefox http://localhost:5000
Icon=familiar
Terminal=false
Type=Application
Categories=Utility;Network;
StartupNotify=true
DESKENTRY

# ── Install plasmoid ──────────────────────────────────────────────────────────
if [[ -d /opt/magichat/plasma-applet/familiar-applet ]]; then
    mkdir -p /usr/share/plasma/plasmoids/
    cp -r /opt/magichat/plasma-applet/familiar-applet \
          /usr/share/plasma/plasmoids/com.magichat.familiar
    kbuildsycoca6 --noincremental 2>/dev/null || true
fi

# ── Install systemd units ─────────────────────────────────────────────────────
for unit in /opt/magichat/systemd/*.service /opt/magichat/systemd/*.timer; do
    [[ -f "$unit" ]] && cp "$unit" /etc/systemd/system/
done
systemctl daemon-reload
systemctl enable reflection.service 2>/dev/null || true
systemctl enable magichat-ollama.service 2>/dev/null || true
systemctl enable magichat-profile-setup.service 2>/dev/null || true
systemctl enable magichat-wizard.service 2>/dev/null || true

# ── Ollama LLM inference ──────────────────────────────────────────────────────
curl -fsSL https://ollama.com/install.sh | OLLAMA_INSTALL_ONLY=1 sh 2>/dev/null || true
mkdir -p /var/lib/magichat/models
chown magichat:magichat /var/lib/magichat/models
cat > /etc/magichat/ollama.env << 'OLLAMAENV'
OLLAMA_HOST=127.0.0.1:11434
OLLAMA_MODELS=/var/lib/magichat/models
OLLAMA_NUM_PARALLEL=4
OLLAMA_MAX_LOADED_MODELS=2
OLLAMA_FLASH_ATTENTION=1
OLLAMA_KEEP_ALIVE=10m
OLLAMAENV

# ── AI providers config (empty — set by firstboot wizard) ────────────────────
cat > /etc/magichat/providers.env << 'PROVIDERSENV'
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GEMINI_API_KEY=
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.2
DEFAULT_PROVIDER=auto
FAMILIAR_PHI_LOCAL_ONLY=false
PROVIDERSENV
chmod 600 /etc/magichat/providers.env
chown magichat:magichat /etc/magichat/providers.env

# ── Optional profile setup — security_suite and network_ops ──────────────────
# These profiles are opt-in (not always_on) and are NOT installed during %post.
# They are installed by magichat-profile-setup.service on first boot when
# the user selects them in the desktop wizard (ProfilePage.qml).
# This section just ensures the profile scripts are executable.
for profile_script in \
    /opt/magichat/scripts/profiles/security-suite.sh \
    /opt/magichat/scripts/profiles/network-ops.sh; do
    [[ -f "${profile_script}" ]] && chmod +x "${profile_script}"
done

# Create stub env files so the security/network skills can find their config
# directories even before the user installs the profiles.
mkdir -p /etc/magichat
for env_file in wazuh.env crowdsec.env suricata.env netdata.env uptime-kuma.env; do
    touch "/etc/magichat/${env_file}"
done

# ── Polkit rules (no root prompts for profile installs) ───────────────────────
if [[ -d /opt/magichat/security/polkit ]]; then
    cp /opt/magichat/security/polkit/*.rules /etc/polkit-1/rules.d/
fi

# ── Firewall ──────────────────────────────────────────────────────────────────
if [[ -f /opt/magichat/firewall/magichat.xml ]]; then
    cp /opt/magichat/firewall/magichat.xml /etc/firewalld/zones/
fi

# ── Security hardening ────────────────────────────────────────────────────────
cp /opt/magichat/security/sshd_magichat.conf /etc/ssh/sshd_config.d/99-magichat.conf 2>/dev/null || true
cp /opt/magichat/security/sysctl-hardening.conf /etc/sysctl.d/99-magichat.conf 2>/dev/null || true
cp /opt/magichat/security/audit.rules /etc/audit/rules.d/99-magichat.rules 2>/dev/null || true
systemctl enable auditd 2>/dev/null || true

# ── GPU detection ─────────────────────────────────────────────────────────────
if [[ -f /opt/magichat/scripts/detect-gpu.sh ]]; then
    chmod +x /opt/magichat/scripts/detect-gpu.sh
    /opt/magichat/scripts/detect-gpu.sh --install 2>/dev/null || true
fi

# ── First-boot marker ─────────────────────────────────────────────────────────
touch /opt/magichat/.needs-firstboot

# ── MOTD ──────────────────────────────────────────────────────────────────────
cat > /etc/motd << 'MOTD'

  ╔═══════════════════════════════════════╗
  ║           🎩  Magic Hat               ║
  ║   Familiar AI Desktop Platform        ║
  ║                                       ║
  ║  Dashboard: http://localhost:5000     ║
  ║  CLI:       magichat status           ║
  ╚═══════════════════════════════════════╝

MOTD

echo "=== Magic Hat Desktop post-install complete: $(date) ==="

%end
