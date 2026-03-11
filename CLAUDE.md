# Magic Hat — Purpose-Built Linux Server for Familiar AI

- **Version**: 0.1.0
- **Base OS**: Fedora Server (latest stable)
- **License**: MIT
- **Heritage**: Red Hat lineage (George co-developed Yellow Hat kernel)

## Structure

```
kickstart/          # Fedora Kickstart file for ISO generation
systemd/            # Service unit files
nginx/              # Reverse proxy configuration
firewall/           # firewalld zones + fail2ban config
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
```

## Architecture

Magic Hat wraps Reflection (which wraps Familiar) into a server appliance:
- `reflection.service` — systemd-managed, watchdog, security-hardened
- PostgreSQL + Redis — auto-configured with random passwords
- Nginx — reverse proxy, TLS 1.3, security headers
- SELinux — enforcing mode with custom policies
- fail2ban — brute-force protection
- dnf-automatic — security patches

## Dependencies

- `reflection-agent[full]` from PyPI (installed via pip in the image)
- Fedora Server packages: postgresql-server, redis, nginx, podman, fail2ban
