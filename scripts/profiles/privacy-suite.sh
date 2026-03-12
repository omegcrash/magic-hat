#!/usr/bin/env bash
# Magic Hat — Privacy Suite Profile (Sprint 5 full implementation)
# Configures: Pi-hole (localhost DNS), SearXNG (private search),
# NetworkManager DNS routing, Nginx reverse proxy for Pi-hole admin,
# kernel hardening, firewall rules.
#
# Pi-hole and SearXNG are provisioned via Familiar ServiceManager at first
# Familiar startup. This script configures the OS-level DNS and proxy routing
# so everything works transparently once the containers are running.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

echo "  [privacy-suite] Configuring privacy layer…"

# ── Record desired services (Familiar ServiceManager picks these up) ──────────
mkdir -p /etc/magichat
for SVC in pihole searxng; do
    grep -q "${SVC}" /etc/magichat/desired-services.conf 2>/dev/null || \
        echo "${SVC}" >> /etc/magichat/desired-services.conf
done

# ── NetworkManager: route DNS through Pi-hole ────────────────────────────────
# When Pi-hole container is running on localhost:53, all system DNS goes through it.
# If Pi-hole is not running, NetworkManager falls back to DHCP-provided DNS.
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-magichat-pihole-dns.conf << 'NMDNS'
[main]
# Do not auto-configure DNS — use our managed stub
dns=none

[connection-default-policy]
# Force localhost DNS when Pi-hole is running; NetworkManager manages fallback
# via the systemd-resolved stub at 127.0.0.53 (kept active as fallback)
ipv4.dns=127.0.0.1
ipv4.dns-priority=-100
ipv6.dns=::1
ipv6.dns-priority=-100
NMDNS

# ── systemd-resolved: stub listener for fallback ─────────────────────────────
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/99-magichat-pihole.conf << 'RESOLVED'
[Resolve]
# Allow Pi-hole to take over port 53; resolved listens on 127.0.0.53 only
DNSStubListener=yes
DNS=127.0.0.1
FallbackDNS=9.9.9.9 149.112.112.112
RESOLVED

# ── /etc/resolv.conf → Pi-hole first, resolved as fallback ───────────────────
# Write a managed resolv.conf. Symlinked to systemd-resolved stub by default on
# Fedora; we override it so Pi-hole takes priority when running.
cat > /etc/resolv.conf << 'RESOLV'
# Magic Hat Privacy Suite — managed by magichat-privacy-suite
# Pi-hole handles DNS blocking; systemd-resolved stub is the fallback.
nameserver 127.0.0.1
nameserver 127.0.0.53
options edns0 trust-ad
RESOLV

# Mark it immutable so NetworkManager doesn't clobber it
# (chattr only works on real filesystems; ignore errors in containers/CI)
chattr +i /etc/resolv.conf 2>/dev/null || true

# ── Nginx: reverse proxy for Pi-hole admin panel ─────────────────────────────
# Pi-hole listens on 127.0.0.1:8053. Nginx exposes /pihole/ → http://localhost/pihole/
NGINX_CONF_DIR="/etc/nginx/conf.d"
if [[ -d "${NGINX_CONF_DIR}" ]]; then
    cp /opt/magichat/nginx/pihole.conf "${NGINX_CONF_DIR}/pihole.conf" 2>/dev/null || true
    systemctl reload nginx 2>/dev/null || true
fi

# ── Kernel hardening ──────────────────────────────────────────────────────────
if [[ -f /opt/magichat/security/sysctl-hardening.conf ]]; then
    cp /opt/magichat/security/sysctl-hardening.conf /etc/sysctl.d/99-magichat-security.conf
    sysctl --system 2>/dev/null || true
fi

# ── firewalld: drop inbound ICMP echo (ping) ─────────────────────────────────
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-icmp-block=echo-request 2>/dev/null || true
    firewall-cmd --permanent --add-icmp-block=echo-reply   2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi

# ── Firefox about:config overrides for privacy ───────────────────────────────
# Written to autoconfig — runs on every Firefox launch (no profile dependency)
FIREFOX_DIST="/usr/lib64/firefox/distribution"
[[ -d /usr/lib/firefox/distribution ]] && FIREFOX_DIST="/usr/lib/firefox/distribution"
mkdir -p "${FIREFOX_DIST}"

cat > "${FIREFOX_DIST}/policies.json" << 'FFPOLICIES'
{
  "policies": {
    "Homepage": { "URL": "http://localhost:5000", "Locked": false, "StartPage": "homepage" },
    "NewTabPage": "about:blank",
    "DisplayBookmarksToolbar": "always",
    "ManagedBookmarks": [
      { "name": "Familiar Dashboard", "url": "http://localhost:5000" },
      { "name": "SearXNG Search",     "url": "http://localhost:8888" },
      { "name": "Pi-hole Admin",      "url": "http://localhost/pihole/" },
      { "name": "Joplin Notes",       "url": "http://localhost:22300" },
      { "name": "Gitea",              "url": "http://localhost:3000" },
      { "name": "Mealie Recipes",     "url": "http://localhost:9925" },
      { "name": "Jellyfin",           "url": "http://localhost:8096" },
      { "name": "Nextcloud",          "url": "http://localhost:8080" }
    ],
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "PasswordManagerEnabled": false,
    "SearchEngines": {
      "Add": [
        {
          "Name": "SearXNG (private)",
          "URLTemplate": "http://localhost:8888/search?q={searchTerms}",
          "Method": "GET",
          "IconURL": "http://localhost:8888/favicon.svg",
          "Alias": "@sx"
        }
      ],
      "Default": "SearXNG (private)"
    },
    "DNSOverHTTPS": { "Enabled": false }
  }
}
FFPOLICIES

echo "  [privacy-suite] Done"
echo "  [privacy-suite] NOTE: DNS routing active — Pi-hole containers must be"
echo "  [privacy-suite]       running for full ad blocking. Start via Familiar"
echo "  [privacy-suite]       dashboard → Services → Pi-hole."
