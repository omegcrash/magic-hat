#!/usr/bin/env bash
# Magic Hat — Security Suite Profile
# Installs and configures:
#   - CrowdSec (native dnf — needs nftables root access)
#   - Suricata IDS (native dnf — needs raw sockets)
#   - Wazuh 3-container stack (manager, indexer, dashboard) via Familiar ServiceManager
#   - crowdsec-firewall-bouncer-nftables (auto-bans)
#
# CrowdSec and Suricata are NOT in Familiar SERVICE_SPECS because they require
# root-level nftables/raw-socket access incompatible with Podman. They are
# installed as native RPMs and managed by systemd.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [security-suite] Configuring Security Suite…"

# ── Record desired Familiar services (ServiceManager picks these up) ─────────
mkdir -p /etc/magichat
for SVC in wazuh_manager wazuh_indexer wazuh_dashboard spiderfoot; do
    grep -q "${SVC}" /etc/magichat/desired-services.conf 2>/dev/null || \
        echo "${SVC}" >> /etc/magichat/desired-services.conf
done

# ── Wazuh Indexer requires vm.max_map_count >= 262144 (OpenSearch) ────────────
echo "  [security-suite] Setting vm.max_map_count for Wazuh Indexer…"
cat > /etc/sysctl.d/99-magichat-wazuh.conf << 'SYSCTL'
# Wazuh Indexer (OpenSearch) requires high mmap count
# See: https://opensearch.org/docs/latest/install-and-configure/install-opensearch/index/
vm.max_map_count = 262144
SYSCTL
sysctl -p /etc/sysctl.d/99-magichat-wazuh.conf 2>/dev/null || true

# ── CrowdSec (native dnf — requires nftables root access) ────────────────────
echo "  [security-suite] Installing CrowdSec…"

# Add CrowdSec official repository
if ! rpm -q crowdsec &>/dev/null; then
    curl -fsSL https://packagecloud.io/crowdsec/crowdsec/gpgkey | \
        gpg --dearmor -o /etc/pki/rpm-gpg/GPG-KEY-crowdsec 2>/dev/null || true
    cat > /etc/yum.repos.d/crowdsec.repo << 'CROWDSEC_REPO'
[crowdsec]
name=CrowdSec Security Engine
baseurl=https://packagecloud.io/crowdsec/crowdsec/fedora/$releasever/$basearch
repo_gpgcheck=0
gpgcheck=0
enabled=1
CROWDSEC_REPO

    dnf install -y crowdsec 2>/dev/null || \
        echo "  WARNING: CrowdSec install failed — may need manual repo setup"
fi

# Install nftables bouncer (auto-bans threat actors at firewall level)
if ! rpm -q crowdsec-firewall-bouncer-nftables &>/dev/null; then
    dnf install -y crowdsec-firewall-bouncer-nftables 2>/dev/null || \
        echo "  WARNING: crowdsec-firewall-bouncer-nftables not available"
fi

# Write CrowdSec config
if [ -d /etc/crowdsec ]; then
    cat > /etc/crowdsec/magichat-overrides.yaml << 'CROWDSEC_CFG'
# Magic Hat CrowdSec overrides
# CrowdSec LAPI is the default local socket + optional HTTP on 127.0.0.1:8080
api:
  server:
    listen_uri: "127.0.0.1:8080"
    log_level: "info"

# Collections — install best-practice rules
# crowdsec-cli cscli collections install crowdsecurity/linux
# crowdsec-cli cscli collections install crowdsecurity/nginx
# crowdsec-cli cscli collections install crowdsecurity/ssh
CROWDSEC_CFG

    # Install common detection collections (non-interactive)
    if command -v cscli &>/dev/null; then
        cscli collections install \
            crowdsecurity/linux \
            crowdsecurity/nginx \
            crowdsecurity/ssh-bf \
            2>/dev/null || echo "  NOTE: cscli collections install requires internet access"
    fi
fi

# Record Familiar API endpoint for crowdsec skill
mkdir -p /etc/magichat
cat > /etc/magichat/crowdsec.env << 'CSENV'
# CrowdSec LAPI endpoint for Familiar skills/crowdsec/skill.py
# Generate API key with: cscli bouncers add familiar-agent
CROWDSEC_URL=http://127.0.0.1:8080
CROWDSEC_API_KEY=
CSENV

systemctl enable crowdsec 2>/dev/null || true
systemctl enable crowdsec-firewall-bouncer 2>/dev/null || true

# ── Suricata IDS (native dnf — needs AF_PACKET raw sockets) ──────────────────
echo "  [security-suite] Installing Suricata IDS…"

if ! rpm -q suricata &>/dev/null; then
    dnf install -y suricata 2>/dev/null || \
        echo "  WARNING: Suricata install failed — check EPEL is enabled"
fi

if [ -f /etc/suricata/suricata.yaml ]; then
    # Configure EVE JSON logging path (Familiar skill reads from here)
    sed -i 's|filename: eve.json|filename: /var/log/suricata/eve.json|g' \
        /etc/suricata/suricata.yaml 2>/dev/null || true

    # Auto-detect primary interface and update Suricata config
    PRIMARY_IF=$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')
    if [ -n "${PRIMARY_IF:-}" ]; then
        sed -i "s|interface: eth0|interface: ${PRIMARY_IF}|g" \
            /etc/suricata/suricata.yaml 2>/dev/null || true
        echo "  [security-suite] Suricata interface: ${PRIMARY_IF}"
    fi

    # Update signatures (requires internet)
    if command -v suricata-update &>/dev/null; then
        suricata-update 2>/dev/null || echo "  NOTE: Suricata rule update requires internet access"
    fi
fi

# Record EVE log path for Familiar sysaudit skill
cat > /etc/magichat/suricata.env << 'SENV'
# Suricata EVE JSON log path for Familiar skills/sysaudit/skill.py
SURICATA_EVE_LOG=/var/log/suricata/eve.json
SENV

systemctl enable suricata 2>/dev/null || true

# ── Wazuh agent (optional — connects to Wazuh manager container) ──────────────
# The Wazuh manager/indexer/dashboard run as Podman containers (provisioned by
# Familiar ServiceManager). We optionally enroll a local Wazuh agent here.
echo "  [security-suite] Setting up Wazuh agent enrollment…"

mkdir -p /etc/magichat
cat > /etc/magichat/wazuh.env << 'WENV'
# Wazuh API credentials for Familiar skills/wazuh/skill.py
# These are set after wazuh_manager container is first started.
# Manager API:
WAZUH_HOST=http://localhost:55000
WAZUH_USER=wazuh-wui
WAZUH_PASSWORD=
WAZUH_VERIFY_SSL=false
# Indexer (OpenSearch — security plugin disabled for self-hosted):
WAZUH_INDEXER=http://localhost:9200
WAZUH_INDEXER_USER=admin
WAZUH_INDEXER_PASSWORD=SecretPassword
WENV

echo "  [security-suite] Done. Start Wazuh containers with:"
echo "    familiar service provision wazuh_manager wazuh_indexer wazuh_dashboard"
echo "  Then enroll Wazuh agent with:"
echo "    magichat siem enroll \$(hostname)"
echo "  And configure CrowdSec API key with:"
echo "    cscli bouncers add familiar-agent"
echo "    # Then add to /etc/magichat/crowdsec.env"

# ── Auditd hardening for security posture ─────────────────────────────────────
if command -v auditctl &>/dev/null; then
    auditctl -e 2 2>/dev/null || true  # Immutable audit rules
    systemctl enable auditd 2>/dev/null || true
fi

echo "  [security-suite] Security Suite profile complete."
