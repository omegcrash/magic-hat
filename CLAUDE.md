# Magic Hat — Purpose-Built Linux Server for Familiar AI

- **Version**: 0.2.0
- **Base OS**: Fedora Server (latest stable)
- **License**: MIT
- **Heritage**: Red Hat lineage (George co-developed Yellow Hat kernel)

## Structure

```
kickstart/          # Fedora Kickstart file for ISO generation
systemd/            # Service unit files (hardened with seccomp + syscall filters)
nginx/              # Reverse proxy (rate limiting, CSP, WAF rules)
firewall/           # firewalld zones + fail2ban (8 jails + custom filters)
security/           # Hardening configs (SSH, kernel, audit, seccomp, output filter)
scripts/            # CLI tools (magichat), installer, backup, ISO builder
firstboot/          # First-boot wizard (planned)
ci/                 # GitHub Actions workflow
```

## Key Commands

```bash
# Build ISO (requires Fedora host with lorax)
sudo ./scripts/build-iso.sh

# Install on existing Fedora Server
curl -fsSL https://raw.githubusercontent.com/omegcrash/magic-hat/master/scripts/install.sh | sudo bash

# Server management
magichat status     # Show service health
magichat setup      # Configure domain + TLS
magichat admin      # Create admin user
magichat update     # Update OS + Reflection
magichat backup     # Run database backup
magichat logs       # Follow service logs
magichat harden     # Run security audit (--apply to auto-fix)
magichat audit      # Show 24h security audit log
```

## Architecture

Magic Hat wraps Reflection (which wraps Familiar) into a server appliance:
- `reflection.service` — systemd-managed, watchdog, security-hardened
- PostgreSQL + Redis — auto-configured with random passwords
- Nginx — reverse proxy, TLS 1.3, security headers, rate limiting
- SELinux — enforcing mode with custom policies
- fail2ban — 8 jails: SSH, Nginx auth/rate/bot/blocked, API abuse, auth brute force, recidive
- dnf-automatic — security patches
- auditd — immutable audit trail for all security-critical events
- AIDE — file integrity monitoring

## Security Model (OWASP Agentic Top 10 + CIS)

```
security/
├── sshd_magichat.conf       # SSH: Ed25519 only, cert auth ready, no root, no forwarding
├── ssh_banner                # Legal warning banner
├── sysctl-hardening.conf     # Kernel: ASLR, ptrace restrict, SYN cookies, no redirects
├── audit.rules               # Audit: auth events, config changes, privilege escalation
├── seccomp-reflection.json   # Syscall filter: whitelist-only for Reflection process
├── output-filter.conf        # Agent output sanitizer: PII/credential/PHI pattern matching
└── hardening.sh              # 8-section audit script with auto-fix (--apply)
```

### OWASP Agentic Coverage
| Threat | Mitigation |
|--------|-----------|
| ASI01 Goal Hijacking | fail2ban rate limiting, Constitution enforcement |
| ASI02 Tool Misuse | seccomp syscall filter, systemd SystemCallFilter |
| ASI03 Privilege Escalation | CapabilityBoundingSet=, NoNewPrivileges, audit trail |
| ASI05 Memory Poisoning | Data directory permissions, AIDE integrity checks |
| ASI06 Data Leakage | output-filter.conf pattern matching (PII/PHI/credentials) |
| ASI07 Supply Chain | AIDE baseline, crypto-policies FUTURE, hash verification |
| ASI08 Monitoring | auditd + journald + fail2ban + hardening.sh audit |
| ASI09 Multi-Agent Trust | Signal Protocol encryption, mesh permissions |

## Dependencies

- `reflection-agent[full]` from PyPI (installed via pip in the image)
- Fedora Server packages: postgresql-server, redis, nginx, podman, fail2ban, audit, aide
