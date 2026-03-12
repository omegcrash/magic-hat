#!/usr/bin/env bash
# Magic Hat — Privacy Suite Profile (always-on)
# Configures Pi-hole, SearXNG, firewall hardening, optional home encryption
#
# Called from kickstart %post — safe to re-run.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [privacy-suite] Configuring privacy layer…"

# ── Pi-hole + SearXNG desired service flags ───────────────────────────────────
mkdir -p /etc/magichat
for SVC in pihole searxng; do
    echo "${SVC}" >> /etc/magichat/desired-services.conf
done

# ── Firefox privacy policies (appended to existing) ──────────────────────────
# (Primary Firefox policies are written by kde-configure.sh)
# Add privacy-specific settings here if needed in future.

# ── DNS-over-HTTPS stub for Pi-hole awareness ─────────────────────────────────
# When Pi-hole is running (localhost:53), configure NetworkManager to use it
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-magichat-dns.conf << 'NMDNS'
[main]
# Use Pi-hole on localhost when running
dns=none

[connection]
ipv4.dns=127.0.0.1
ipv4.dns-priority=-100
NMDNS

# ── Kernel hardening ──────────────────────────────────────────────────────────
if [[ -f /opt/magichat/security/sysctl-hardening.conf ]]; then
    cp /opt/magichat/security/sysctl-hardening.conf /etc/sysctl.d/99-magichat.conf
    sysctl --system 2>/dev/null || true
fi

# ── firewalld: drop ICMP ping responses ───────────────────────────────────────
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-icmp-block=echo-request 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi

echo "  [privacy-suite] Done"
