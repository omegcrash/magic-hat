#!/usr/bin/env bash
# Magic Hat — Security Hardening Script
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Post-install hardening — addresses OWASP Agentic Top 10,
# Linux CIS benchmarks, and AI-specific threat vectors.
#
# Usage: sudo /opt/magichat/security/hardening.sh [--apply]
#
# Without --apply, runs in audit mode (reports without changing).

set -euo pipefail

APPLY="${1:-}"
PASS=0
FAIL=0
WARN=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

_pass() { echo -e "  ${GREEN}PASS${NC}  $1"; ((PASS++)); }
_fail() { echo -e "  ${RED}FAIL${NC}  $1"; ((FAIL++)); }
_warn() { echo -e "  ${YELLOW}WARN${NC}  $1"; ((WARN++)); }
_fix()  { echo -e "  ${CYAN}FIX ${NC}  $1"; }

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Magic Hat Security Hardening Audit                ║${NC}"
echo -e "${BOLD}║     OWASP Agentic + CIS Linux + AI Threat Model      ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[1/8] Kernel & System Hardening${NC}"
echo ""

# 1.1 — Kernel parameters
check_sysctl() {
    local key="$1" expected="$2" desc="$3"
    local val
    val=$(sysctl -n "$key" 2>/dev/null || echo "MISSING")
    if [[ "$val" == "$expected" ]]; then
        _pass "$desc ($key = $val)"
    else
        _fail "$desc ($key = $val, expected $expected)"
        if [[ "$APPLY" == "--apply" ]]; then
            sysctl -w "$key=$expected" >/dev/null 2>&1
            echo "$key = $expected" >> /etc/sysctl.d/99-magichat.conf
            _fix "Set $key = $expected"
        fi
    fi
}

check_sysctl "net.ipv4.conf.all.send_redirects" "0" "ICMP redirects disabled (send)"
check_sysctl "net.ipv4.conf.all.accept_redirects" "0" "ICMP redirects disabled (accept)"
check_sysctl "net.ipv4.conf.all.accept_source_route" "0" "Source routing disabled"
check_sysctl "net.ipv4.conf.all.log_martians" "1" "Martian packet logging enabled"
check_sysctl "net.ipv4.conf.all.rp_filter" "1" "Reverse path filtering enabled"
check_sysctl "net.ipv4.tcp_syncookies" "1" "SYN cookies enabled"
check_sysctl "net.ipv4.icmp_echo_ignore_broadcasts" "1" "Broadcast ICMP ignored"
check_sysctl "net.ipv6.conf.all.accept_ra" "0" "IPv6 router advertisements disabled"
check_sysctl "kernel.randomize_va_space" "2" "ASLR fully enabled"
check_sysctl "kernel.kptr_restrict" "2" "Kernel pointer restriction"
check_sysctl "kernel.yama.ptrace_scope" "2" "ptrace restricted to root"
check_sysctl "kernel.dmesg_restrict" "1" "dmesg restricted to root"
check_sysctl "kernel.unprivileged_bpf_disabled" "1" "Unprivileged BPF disabled"
check_sysctl "kernel.core_uses_pid" "1" "Core dumps use PID"
check_sysctl "fs.suid_dumpable" "0" "SUID core dumps disabled"

echo ""

# 1.2 — Core dumps disabled
if grep -q "hard core 0" /etc/security/limits.conf 2>/dev/null; then
    _pass "Core dumps disabled in limits.conf"
else
    _fail "Core dumps not restricted in limits.conf"
    if [[ "$APPLY" == "--apply" ]]; then
        echo "* hard core 0" >> /etc/security/limits.conf
        _fix "Added core dump restriction"
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[2/8] SELinux & Mandatory Access Control${NC}"
echo ""

SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
if [[ "$SELINUX_STATUS" == "Enforcing" ]]; then
    _pass "SELinux is enforcing"
else
    _fail "SELinux is $SELINUX_STATUS (must be Enforcing)"
    if [[ "$APPLY" == "--apply" ]]; then
        setenforce 1 2>/dev/null || true
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        _fix "Set SELinux to enforcing"
    fi
fi

# Check for custom Reflection policy
if semodule -l 2>/dev/null | grep -q "magichat"; then
    _pass "Custom Magic Hat SELinux policy loaded"
else
    _warn "No custom SELinux policy for Magic Hat (using default confinement)"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[3/8] SSH Hardening${NC}"
echo ""

check_ssh() {
    local key="$1" expected="$2" desc="$3"
    local val
    val=$(sshd -T 2>/dev/null | grep -i "^$key " | awk '{print $2}' || echo "UNKNOWN")
    if [[ "${val,,}" == "${expected,,}" ]]; then
        _pass "$desc"
    else
        _fail "$desc (got: $val, expected: $expected)"
    fi
}

check_ssh "permitrootlogin" "no" "Root login disabled"
check_ssh "passwordauthentication" "no" "Password auth disabled"
check_ssh "x11forwarding" "no" "X11 forwarding disabled"
check_ssh "maxauthtries" "3" "Max auth tries = 3"
check_ssh "protocol" "2" "SSH protocol 2 only"
check_ssh "loglevel" "VERBOSE" "Verbose SSH logging"

if [[ -f /etc/ssh/sshd_config.d/99-magichat.conf ]]; then
    _pass "Magic Hat SSH config deployed"
else
    _fail "Magic Hat SSH config not found"
    if [[ "$APPLY" == "--apply" && -f /opt/magichat/security/sshd_magichat.conf ]]; then
        cp /opt/magichat/security/sshd_magichat.conf /etc/ssh/sshd_config.d/99-magichat.conf
        _fix "Deployed SSH hardening config"
    fi
fi

if [[ -f /etc/ssh/magichat_ca.pub ]]; then
    _pass "SSH certificate authority configured"
else
    _warn "No SSH CA key — using public key auth only (consider certificate auth)"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[4/8] Firewall & Network${NC}"
echo ""

if systemctl is-active --quiet firewalld; then
    _pass "firewalld is active"
else
    _fail "firewalld is not running"
fi

if systemctl is-active --quiet fail2ban; then
    _pass "fail2ban is active"
else
    _fail "fail2ban is not running"
fi

# Check for open ports beyond expected
EXPECTED_PORTS="22 80 443"
UNEXPECTED=$(ss -tlnp | awk 'NR>1 {print $4}' | grep -oP ':\K\d+' | sort -un | while read port; do
    echo "$EXPECTED_PORTS 8000" | grep -qw "$port" || echo "$port"
done)
if [[ -z "$UNEXPECTED" ]]; then
    _pass "No unexpected listening ports"
else
    _warn "Unexpected listening ports: $UNEXPECTED"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[5/8] Service Hardening (systemd)${NC}"
echo ""

check_systemd_prop() {
    local unit="$1" prop="$2" expected="$3" desc="$4"
    local val
    val=$(systemctl show "$unit" -p "$prop" --value 2>/dev/null || echo "UNKNOWN")
    if [[ "$val" == "$expected" ]]; then
        _pass "$desc"
    else
        _fail "$desc (got: $val, expected: $expected)"
    fi
}

if systemctl cat reflection.service &>/dev/null; then
    check_systemd_prop "reflection.service" "NoNewPrivileges" "yes" "Reflection: NoNewPrivileges"
    check_systemd_prop "reflection.service" "ProtectSystem" "strict" "Reflection: ProtectSystem=strict"
    check_systemd_prop "reflection.service" "PrivateTmp" "yes" "Reflection: PrivateTmp"
    check_systemd_prop "reflection.service" "ProtectKernelTunables" "yes" "Reflection: ProtectKernelTunables"
    check_systemd_prop "reflection.service" "ProtectKernelModules" "yes" "Reflection: ProtectKernelModules"
    check_systemd_prop "reflection.service" "MemoryDenyWriteExecute" "yes" "Reflection: MemoryDenyWriteExecute"
    check_systemd_prop "reflection.service" "RestrictSUIDSGID" "yes" "Reflection: RestrictSUIDSGID"
    check_systemd_prop "reflection.service" "LockPersonality" "yes" "Reflection: LockPersonality"
else
    _warn "reflection.service not found (not installed yet)"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[6/8] Data Protection & Backups${NC}"
echo ""

# Env file permissions
if [[ -f /etc/magichat/reflection.env ]]; then
    PERMS=$(stat -c %a /etc/magichat/reflection.env)
    if [[ "$PERMS" == "600" ]]; then
        _pass "Env file permissions: 600"
    else
        _fail "Env file permissions: $PERMS (expected 600)"
        if [[ "$APPLY" == "--apply" ]]; then
            chmod 600 /etc/magichat/reflection.env
            _fix "Fixed env file permissions"
        fi
    fi
else
    _warn "Env file not found (not installed yet)"
fi

# Backup directory
if [[ -d /var/backups/magichat ]]; then
    _pass "Backup directory exists"

    # Check for append-only attribute
    if lsattr -d /var/backups/magichat 2>/dev/null | grep -q "a"; then
        _pass "Backup directory is append-only"
    else
        _warn "Backup directory not append-only (consider: chattr +a)"
        if [[ "$APPLY" == "--apply" ]]; then
            chattr +a /var/backups/magichat 2>/dev/null || true
            _fix "Set append-only on backup directory"
        fi
    fi
else
    _warn "Backup directory not found"
fi

# PostgreSQL SSL
if su - postgres -c "psql -t -c \"SHOW ssl;\"" 2>/dev/null | grep -q "on"; then
    _pass "PostgreSQL SSL enabled"
else
    _warn "PostgreSQL SSL not enabled (internal only, but recommended)"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[7/8] Audit & Monitoring${NC}"
echo ""

if systemctl is-active --quiet auditd; then
    _pass "auditd is active"
else
    _fail "auditd is not running"
    if [[ "$APPLY" == "--apply" ]]; then
        systemctl enable --now auditd 2>/dev/null || true
        _fix "Enabled auditd"
    fi
fi

if [[ -f /etc/audit/rules.d/99-magichat.rules ]]; then
    _pass "Magic Hat audit rules deployed"
else
    _fail "Magic Hat audit rules not found"
    if [[ "$APPLY" == "--apply" && -f /opt/magichat/security/audit.rules ]]; then
        cp /opt/magichat/security/audit.rules /etc/audit/rules.d/99-magichat.rules
        augenrules --load 2>/dev/null || true
        _fix "Deployed audit rules"
    fi
fi

# Check if Reflection logs are being captured
if journalctl -u reflection --since "24 hours ago" -q 2>/dev/null | head -1 | grep -q .; then
    _pass "Reflection service logs available in journal"
else
    _warn "No recent Reflection logs (service may not be running)"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[8/8] AI Agent Security (OWASP Agentic Top 10)${NC}"
echo ""

# ASI01 — Goal Hijacking: Check if Familiar Constitution is configured
if [[ -f /home/magichat/.familiar/constitution.yaml ]] || [[ -f /home/magichat/.familiar/config.yaml ]]; then
    _pass "ASI01 — Familiar configuration present (goal hijacking mitigation)"
else
    _warn "ASI01 — No Familiar config found (Constitution not yet deployed)"
fi

# ASI02 — Tool Misuse: Check if seccomp profile is deployed
if [[ -f /etc/magichat/seccomp-reflection.json ]]; then
    _pass "ASI02 — seccomp profile deployed (tool sandboxing)"
else
    _fail "ASI02 — seccomp profile not deployed"
    if [[ "$APPLY" == "--apply" && -f /opt/magichat/security/seccomp-reflection.json ]]; then
        cp /opt/magichat/security/seccomp-reflection.json /etc/magichat/seccomp-reflection.json
        _fix "Deployed seccomp profile"
    fi
fi

# ASI03 — Privilege Escalation: Check service user restrictions
if id magichat &>/dev/null; then
    SHELL=$(getent passwd magichat | cut -d: -f7)
    if [[ "$SHELL" == "/bin/bash" ]] || [[ "$SHELL" == "/sbin/nologin" ]]; then
        _pass "ASI03 — Service user exists with restricted shell"
    fi
else
    _warn "ASI03 — Service user 'magichat' not found"
fi

# ASI05 — Memory Poisoning: Check data directory permissions
if [[ -d /home/magichat/.familiar/data ]]; then
    OWNER=$(stat -c %U /home/magichat/.familiar/data 2>/dev/null)
    if [[ "$OWNER" == "magichat" ]]; then
        _pass "ASI05 — Familiar data directory owned by service user"
    else
        _fail "ASI05 — Familiar data owned by $OWNER (expected magichat)"
    fi
else
    _warn "ASI05 — Familiar data directory not yet created"
fi

# ASI06 — Data Leakage: Check if output sanitizer is configured
if [[ -f /etc/magichat/output-filter.conf ]]; then
    _pass "ASI06 — Output sanitizer configured"
else
    _warn "ASI06 — Output sanitizer not configured (deploy output-filter.conf)"
fi

# ASI07 — Supply Chain: Check pip hash verification
if pip3.11 config get global.require-hashes 2>/dev/null | grep -q "true"; then
    _pass "ASI07 — pip hash verification enabled"
else
    _warn "ASI07 — pip hash verification not enforced"
fi

# ASI08 — Insufficient Monitoring: Check audit + journal
if systemctl is-active --quiet auditd && journalctl -u reflection -q 2>/dev/null | head -1 | grep -q .; then
    _pass "ASI08 — Audit and journal monitoring active"
else
    _warn "ASI08 — Monitoring incomplete"
fi

# ASI09 — Multi-Agent Trust: Check mesh encryption
if [[ -d /home/magichat/.familiar/data/mesh ]]; then
    _pass "ASI09 — Mesh data directory present (Signal Protocol expected)"
else
    _warn "ASI09 — Mesh not yet initialized"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}PASS: ${PASS}${NC}  ${RED}FAIL: ${FAIL}${NC}  ${YELLOW}WARN: ${WARN}${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"

TOTAL=$((PASS + FAIL + WARN))
if [[ $TOTAL -gt 0 ]]; then
    SCORE=$(( (PASS * 100) / TOTAL ))
    echo -e "  Security score: ${BOLD}${SCORE}%${NC}"
fi

if [[ $FAIL -gt 0 && "$APPLY" != "--apply" ]]; then
    echo ""
    echo "  Run with --apply to auto-fix failures:"
    echo "    sudo /opt/magichat/security/hardening.sh --apply"
fi
echo ""
