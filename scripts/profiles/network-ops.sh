#!/usr/bin/env bash
# Magic Hat — Network Ops Profile
# Installs and configures:
#   - Cockpit web UI (native dnf — systemd + privileged port 9090)
#   - Netdata real-time metrics (container via Familiar ServiceManager)
#   - Uptime Kuma service monitoring (container via Familiar ServiceManager)
#   - nmap, iperf3, traceroute for network diagnostics
#
# Cockpit is NOT in Familiar SERVICE_SPECS because it requires real systemd
# access and must bind to privileged port 9090. It is installed as a native
# RPM and managed by systemd (cockpit.socket activation).
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [network-ops] Configuring Network Operations profile…"

# ── Record desired Familiar services (ServiceManager picks these up) ─────────
mkdir -p /etc/magichat
for SVC in netdata uptime_kuma; do
    grep -q "${SVC}" /etc/magichat/desired-services.conf 2>/dev/null || \
        echo "${SVC}" >> /etc/magichat/desired-services.conf
done

# ── Cockpit (native dnf — requires real systemd and privileged port) ──────────
echo "  [network-ops] Installing Cockpit web admin UI…"

COCKPIT_PKGS=(
    cockpit                 # Core web console
    cockpit-networkmanager  # Network interface management
    cockpit-storaged        # Storage / disk management
    cockpit-podman          # Container management (view Familiar containers)
    cockpit-pcp             # Performance metrics (PCP/Netdata integration)
    cockpit-selinux         # SELinux policy management
)

dnf install -y "${COCKPIT_PKGS[@]}" 2>/dev/null || {
    echo "  WARNING: Some Cockpit packages unavailable — installing core only"
    dnf install -y cockpit 2>/dev/null || \
        echo "  ERROR: Cockpit install failed"
}

# Enable socket-activated Cockpit (starts on first connection, no idle cost)
systemctl enable --now cockpit.socket 2>/dev/null || true

# Allow Cockpit through firewall
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-service=cockpit 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi

# Generate TLS certificate link for Cockpit
# Cockpit will use the system cert if available (managed by certbot/Magic Hat)
COCKPIT_CERT_DIR="/etc/cockpit/ws-certs.d"
mkdir -p "${COCKPIT_CERT_DIR}"
if [ -f /etc/pki/tls/certs/magichat-selfsigned.pem ]; then
    ln -sf /etc/pki/tls/certs/magichat-selfsigned.pem \
        "${COCKPIT_CERT_DIR}/magichat.cert" 2>/dev/null || true
    ln -sf /etc/pki/tls/private/magichat-selfsigned.key \
        "${COCKPIT_CERT_DIR}/magichat.key" 2>/dev/null || true
fi

echo "  [network-ops] Cockpit available at https://localhost:9090"

# ── Network diagnostic tools ──────────────────────────────────────────────────
echo "  [network-ops] Installing network diagnostic tools…"

dnf install -y \
    nmap            `# Subnet scanning (used by network/skill.py scan_subnet)` \
    iperf3          `# Bandwidth testing (used by network/skill.py test_bandwidth)` \
    traceroute      `# Hop-by-hop routing (traceroute/mtr in network/skill.py)` \
    mtr             `# Better traceroute with packet loss stats` \
    nftables        `# Firewall rules (get_firewall_status reads nft)` \
    bind-utils      `# dig, host, nslookup for DNS diagnostics` \
    net-tools       `# netstat, ifconfig (legacy compat)` \
    iproute         `# ip, ss, tc (modern network tools)` \
    2>/dev/null || echo "  WARNING: Some network tools unavailable"

# ── Netdata configuration ─────────────────────────────────────────────────────
# Netdata runs as a container (provisioned by Familiar ServiceManager).
# Write config that will be volume-mounted into the container.

mkdir -p /etc/magichat
cat > /etc/magichat/netdata.env << 'NENV'
# Netdata API endpoint for Familiar skills/netdata/skill.py
NETDATA_URL=http://localhost:19999
NENV

# ── Uptime Kuma configuration ─────────────────────────────────────────────────
cat > /etc/magichat/uptime-kuma.env << 'UKENV'
# Uptime Kuma API endpoint for Familiar skills/uptime_kuma/skill.py
# Generate an API key in Uptime Kuma Settings > API Keys, then set it here.
UPTIME_KUMA_URL=http://localhost:3001
UPTIME_KUMA_API_KEY=
UKENV

# ── Create network scan cache directory ───────────────────────────────────────
# Familiar workspace.py reads cached scan results from here
FAMILIAR_DATA_DIR="${HOME:-/home/magichat}/.familiar/data/network"
mkdir -p "${FAMILIAR_DATA_DIR}"

echo "  [network-ops] Done."
echo "  Cockpit: https://localhost:9090"
echo "  Netdata + Uptime Kuma will be provisioned automatically."
echo "  Set Uptime Kuma API key in /etc/magichat/uptime-kuma.env after first login."
echo ""
echo "  [network-ops] Network Ops profile complete."
