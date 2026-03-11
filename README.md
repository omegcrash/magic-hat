# Magic Hat

Purpose-built Linux server for the Familiar AI ecosystem.

Built on Fedora Server. Hosts [Reflection](https://github.com/omegcrash/reflection) (multi-tenant AI platform), the skill marketplace, chain registry, and licensing services.

## The Magic Trilogy

| Tier | Project | Role |
|------|---------|------|
| Agent | [Familiar](https://github.com/omegcrash/familiar) | Personal AI companion |
| Platform | [Reflection](https://github.com/omegcrash/reflection) | Enterprise multi-tenant platform |
| Server OS | **Magic Hat** | Infrastructure, marketplace, chain, licensing |

## Quick Start

Download the latest ISO from [Releases](https://github.com/omegcrash/magic-hat/releases), boot it, and follow the first-boot wizard.

Or install on an existing Fedora Server:

```bash
curl -fsSL https://raw.githubusercontent.com/omegcrash/magic-hat/master/scripts/install.sh | sudo bash
```

## What's Included

- **Reflection** multi-tenant AI platform (FastAPI + PostgreSQL + Redis)
- **Nginx** reverse proxy with auto-TLS (Let's Encrypt)
- **Podman** container runtime (rootless by default)
- **SELinux** enforcing mode with custom policies
- **firewalld** hardened (SSH + HTTPS only)
- **Automatic backups** (PostgreSQL pg_dump, encrypted, on cron)
- **First-boot wizard** (hostname, admin, domain, TLS)

## Building the ISO

Requires a Fedora host with `lorax` and `anaconda`:

```bash
sudo dnf install lorax anaconda
./scripts/build-iso.sh
```

## Heritage

Built on the Red Hat/Fedora lineage. The name is a nod to Red Hat and the magic theme of the Familiar ecosystem.

## License

MIT - see [LICENSE](LICENSE)
