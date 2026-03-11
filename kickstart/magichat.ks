# Magic Hat — Fedora Server Kickstart
# Purpose-built Linux server for the Familiar AI ecosystem
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Usage:
#   livemedia-creator --ks magichat.ks --no-virt --resultdir /tmp/magichat-iso
#   OR boot Fedora netinstall with: inst.ks=https://raw.githubusercontent.com/omegcrash/magic-hat/master/kickstart/magichat.ks

# ── Base ─────────────────────────────────────────────────────────────────────
text
lang en_US.UTF-8
keyboard us
timezone UTC --utc
selinux --enforcing
firewall --enabled --ssh --http --https
rootpw --lock
firstboot --disable
reboot

# ── Storage ──────────────────────────────────────────────────────────────────
autopart --type=lvm --fstype=xfs
zerombr
clearpart --all --initlabel

# ── Network ──────────────────────────────────────────────────────────────────
network --bootproto=dhcp --device=link --activate --hostname=magichat.local

# ── Package Selection ────────────────────────────────────────────────────────
%packages --excludedocs
@^server-product-environment

# Core services
postgresql-server
postgresql-contrib
redis
nginx
certbot
python3-certbot-nginx
podman
podman-compose
fail2ban

# Python environment
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
tmux
screen
htop
iotop
sysstat
git
jq

# Editors
nano
vim-enhanced

# Network tools
curl
wget
bind-utils
net-tools
traceroute

# Hardware detection
lshw
pciutils
usbutils

# Document processing (headless — no GUI, used for PDF conversion + rendering)
libreoffice-headless
libreoffice-writer
libreoffice-calc
libreoffice-impress
poppler-utils

# Fonts (needed for document + PDF rendering)
google-noto-sans-fonts
liberation-fonts-common
liberation-mono-fonts
liberation-sans-fonts
liberation-serif-fonts

# Image processing
ImageMagick

# Media processing (Familiar voice, video, media, transcription skills)
ffmpeg
sox
mediainfo
perl-Image-ExifTool

# OCR + document conversion
ghostscript
pandoc
tesseract
tesseract-langpack-eng

# Hardware monitoring
smartmontools
nvme-cli
lm-sensors

# Crypto + large file support
gnupg2
git-lfs

# Security hardening
audit
aide
openssh-server
policycoreutils-python-utils
setools-console
crypto-policies-scripts

# Remove unnecessary packages
-iwl*firmware*
-plymouth*
-ModemManager
-NetworkManager-wifi
-wpa_supplicant
%end

# ── Post-install ─────────────────────────────────────────────────────────────
%post --log=/root/magichat-install.log

echo "=== Magic Hat post-install: $(date) ==="

# ── Create service user ──────────────────────────────────────────────────────
useradd --system --create-home --shell /bin/bash --comment "Magic Hat service" magichat
usermod -aG wheel magichat

# ── Install Reflection ───────────────────────────────────────────────────────
python3.11 -m pip install --upgrade pip
python3.11 -m pip install "reflection-agent[full]"

# ── PostgreSQL initialization ────────────────────────────────────────────────
postgresql-setup --initdb
# Configure authentication
sed -i 's/ident/scram-sha-256/g' /var/lib/pgsql/data/pg_hba.conf
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '127.0.0.1'/" /var/lib/pgsql/data/postgresql.conf

systemctl enable postgresql
systemctl start postgresql

# Create Reflection database and user
su - postgres -c "psql -c \"CREATE USER reflection WITH PASSWORD 'CHANGEME_ON_FIRST_BOOT';\""
su - postgres -c "psql -c \"CREATE DATABASE reflection OWNER reflection;\""
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE reflection TO reflection;\""

# ── Redis configuration ──────────────────────────────────────────────────────
cat > /etc/redis/redis.conf.d/magichat.conf << 'REDISCONF'
bind 127.0.0.1
requirepass CHANGEME_ON_FIRST_BOOT
maxmemory 256mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
REDISCONF
systemctl enable redis

# ── Nginx reverse proxy ──────────────────────────────────────────────────────
cp /opt/magichat/nginx/reflection.conf /etc/nginx/conf.d/reflection.conf
systemctl enable nginx

# ── Install systemd units ────────────────────────────────────────────────────
cp /opt/magichat/systemd/reflection.service /etc/systemd/system/
cp /opt/magichat/systemd/magichat-backup.service /etc/systemd/system/
cp /opt/magichat/systemd/magichat-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable magichat-ollama.service
systemctl enable reflection.service
systemctl enable magichat-wizard.service
systemctl enable magichat-backup.timer

# ── Firewall ─────────────────────────────────────────────────────────────────
cp /opt/magichat/firewall/magichat.xml /etc/firewalld/zones/
# Will be activated on first boot

# ── fail2ban ─────────────────────────────────────────────────────────────────
cp /opt/magichat/firewall/jail.local /etc/fail2ban/jail.local
systemctl enable fail2ban

# ── dnf-automatic (security updates) ────────────────────────────────────────
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
sed -i 's/upgrade_type = default/upgrade_type = security/' /etc/dnf/automatic.conf
systemctl enable dnf-automatic.timer

# ── Security hardening ─────────────────────────────────────────────────────
# SSH hardening
cp /opt/magichat/security/sshd_magichat.conf /etc/ssh/sshd_config.d/99-magichat.conf
cp /opt/magichat/security/ssh_banner /etc/ssh/magichat_banner

# Kernel hardening
cp /opt/magichat/security/sysctl-hardening.conf /etc/sysctl.d/99-magichat.conf

# Audit rules
cp /opt/magichat/security/audit.rules /etc/audit/rules.d/99-magichat.rules
systemctl enable auditd

# seccomp profile for Reflection
mkdir -p /etc/magichat
cp /opt/magichat/security/seccomp-reflection.json /etc/magichat/seccomp-reflection.json
cp /opt/magichat/security/output-filter.conf /etc/magichat/output-filter.conf

# fail2ban custom filters
cp /opt/magichat/firewall/filter.d/*.conf /etc/fail2ban/filter.d/

# Disable core dumps
echo "* hard core 0" >> /etc/security/limits.conf

# TLS policy — FUTURE crypto policy (strongest available)
update-crypto-policies --set FUTURE 2>/dev/null || true

# AIDE — file integrity baseline (generated on first boot)
aide --init 2>/dev/null || true
cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz 2>/dev/null || true

# ── Ollama LLM inference ───────────────────────────────────────────────────
# Install Ollama binary
curl -fsSL https://ollama.com/install.sh | OLLAMA_INSTALL_ONLY=1 sh 2>/dev/null || true

# Model storage + Ollama env
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

# Install Ollama service + model check
cp /opt/magichat/systemd/magichat-ollama.service /etc/systemd/system/
cp /opt/magichat/scripts/magichat-model-check /usr/local/bin/
chmod +x /usr/local/bin/magichat-model-check

# Initial providers.env (empty keys — configured by wizard or CLI)
cat > /etc/magichat/providers.env << 'PROVIDERSENV'
# Magic Hat — AI Provider Configuration
# Configure with: magichat providers configure
# Or use the first-boot wizard at http://<ip>:8080

ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=claude-sonnet-4-6
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o
GEMINI_API_KEY=
GEMINI_MODEL=gemini-2.5-flash
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.2
DEFAULT_PROVIDER=auto
LIGHTWEIGHT_MODEL=
LIGHTWEIGHT_PROVIDER=
FAMILIAR_PHI_LOCAL_ONLY=false
PROVIDERSENV
chmod 600 /etc/magichat/providers.env
chown magichat:magichat /etc/magichat/providers.env

# Provider management scripts
cp /opt/magichat/scripts/provider-health.sh /opt/magichat/scripts/provider-health.sh 2>/dev/null || true
cp /opt/magichat/scripts/configure-providers.sh /opt/magichat/scripts/configure-providers.sh 2>/dev/null || true
chmod +x /opt/magichat/scripts/provider-health.sh /opt/magichat/scripts/configure-providers.sh 2>/dev/null || true

# GPU groups for service user
usermod -aG render magichat 2>/dev/null || true
usermod -aG video magichat 2>/dev/null || true

# GPU detection + driver install (runs at post-install, best-effort)
if [[ -f /opt/magichat/scripts/detect-gpu.sh ]]; then
    chmod +x /opt/magichat/scripts/detect-gpu.sh
    /opt/magichat/scripts/detect-gpu.sh --install 2>/dev/null || true
fi

# ── Backup cron ──────────────────────────────────────────────────────────────
mkdir -p /var/backups/magichat
chown magichat:magichat /var/backups/magichat

# ── First-boot marker ───────────────────────────────────────────────────────
touch /opt/magichat/.needs-firstboot

# ── Copy Magic Hat files ─────────────────────────────────────────────────────
mkdir -p /opt/magichat
# These are placed by the ISO build process
# /opt/magichat/scripts/    — management scripts
# /opt/magichat/systemd/    — service units
# /opt/magichat/nginx/      — proxy config
# /opt/magichat/firewall/   — firewalld zones + fail2ban
# /opt/magichat/firstboot/  — first-boot wizard

# ── First-boot wizard ─────────────────────────────────────────────────────────
cp /opt/magichat/firstboot/wizard.py /opt/magichat/firstboot/wizard.py 2>/dev/null || true
cp /opt/magichat/systemd/magichat-wizard.service /etc/systemd/system/

# ── MOTD ─────────────────────────────────────────────────────────────────────
cat > /etc/motd << 'MOTD'

  ╔═══════════════════════════════════════╗
  ║           🎩  Magic Hat               ║
  ║     Familiar AI Server Platform       ║
  ║                                       ║
  ║  Setup: http://<ip>:8080               ║
  ║  CLI:   magichat status               ║
  ╚═══════════════════════════════════════╝

MOTD

echo "=== Magic Hat post-install complete: $(date) ==="

%end
