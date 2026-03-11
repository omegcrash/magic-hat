# Magic Hat — Purpose-Built Linux Server for Familiar AI

- **Version**: 0.3.0
- **Base OS**: Fedora Server (latest stable)
- **License**: MIT
- **Heritage**: Red Hat lineage (George co-developed Yellow Hat kernel)

## Structure

```
chain/              # Dross Chain — Python ABCI application (CometBFT consensus engine)
chain/handlers/     # Transaction handlers: registry, dross, provenance (marketplace, licensing planned)
firstboot/          # First-boot web wizard (port 8080, self-disabling)
lib/                # Familiar bridge — runtime introspection of installed familiar-agent package
kickstart/          # Fedora Kickstart file for ISO generation
systemd/            # Service unit files (7 units, hardened with seccomp + syscall filters)
nginx/              # Reverse proxy (rate limiting, CSP, WAF rules)
firewall/           # firewalld zones + fail2ban (8 jails + custom filters)
security/           # Hardening configs (SSH, kernel, audit, seccomp, output filter)
scripts/            # CLI tools (magichat), installer, backup, ISO builder, GPU detection
ci/                 # GitHub Actions workflow
```

## Key Commands

```bash
# Build ISO (requires Fedora host with lorax)
sudo ./scripts/build-iso.sh

# Install on existing Fedora Server
curl -fsSL https://raw.githubusercontent.com/omegcrash/magic-hat/master/scripts/install.sh | sudo bash

# Server management
magichat status          # Show services, GPU, models, system health
magichat setup           # Configure domain + TLS
magichat admin           # Create admin user
magichat update          # Update OS + Ollama + Reflection
magichat backup          # Run database backup
magichat logs <svc>      # Follow service logs
magichat gpu [--install] # Detect GPU, install drivers
magichat models list     # Show installed models
magichat models pull     # Pull model (auto-recommends for your GPU)
magichat models recommend # Show best models for your hardware
magichat desktop enable   # Install GNOME desktop (full daily-driver OS)
magichat desktop disable  # Switch back to headless server
magichat desktop purge    # Remove all desktop packages
magichat desktop status   # Show current mode
magichat harden          # Run security audit (--apply to auto-fix)
magichat audit           # Show 24h security audit log
```

## Desktop Mode (Optional)

Magic Hat ships as a headless server but can become a full desktop OS:

```bash
sudo magichat desktop enable     # ~2-3 GB download, ~5-7 GB disk
sudo magichat desktop disable    # Revert to headless (keeps packages)
sudo magichat desktop purge      # Remove everything, reclaim space
```

Desktop layer includes:
- GNOME desktop (Wayland), GDM login screen
- Firefox + Chromium (homepage set to Familiar dashboard)
- LibreOffice (full GUI, extends existing headless install)
- GIMP, Inkscape, Blender (creative tools for Artist job class)
- Video/audio players, webcam, PipeWire audio
- Printing, scanning, Bluetooth, WiFi
- Flatpak + Flathub (user-installable apps)
- Desktop shortcuts for Dashboard and Magic Hat Terminal

The desktop is a layer on top — all AI services run underneath.
Like Windows vs Windows Server: same core, different interface.

## Architecture

Magic Hat wraps Reflection (which wraps Familiar) into a server appliance:
- `magichat-wizard.service` — First-boot web wizard (7-step, port 8080, self-disables after setup)
- `magichat-ollama.service` — Ollama LLM inference (GPU auto-detected, model management)
- `magichat-chain.service` — CometBFT consensus engine (BFT, P2P, block gossip)
- `magichat-abci.service` — Python ABCI app (genesis registry, Dross economics, provenance)
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

## Dross Chain (Python ABCI + CometBFT)

Three-layer chain: L1 SQLite (local/offline) → L2 CometBFT+ABCI (network consensus) → L3 Ethereum/Base (public bridge).

```
chain/
├── __init__.py          # Package: chain_id=magichat-1, version
├── app.py               # ABCI server: CheckTx, DeliverTx, Query, Commit
├── ipt.py               # IPT constants: K=-260/81, G_φ=φ/√2, GEL formula, stellation numbers
├── state.py             # SQLite state manager: genesis_registry, dross_accounts, provenance_anchors
├── codec.py             # Transaction types + serialization (JSON, RSA-signed)
└── handlers/
    ├── __init__.py      # Handler registry
    ├── registry.py      # Sprint 4: genesis block registration
    ├── dross.py         # Sprint 5: Dross mint/transfer/burn/stake (GEL economics)
    └── provenance.py    # Sprint 6: Merkle root anchoring (C2PA compliance)
```

IPT math reference: George Scott Foley, ORCID 0009-0006-4957-0540
GEL paper: DOI 10.5281/zenodo.18382672

## Familiar Bridge (`lib/familiar_bridge.py`)

Runtime introspection layer that reads from the installed `familiar-agent` package.
Magic Hat uses this to dynamically discover job classes, services, providers, and
health checks — so the OS layer automatically reflects whatever Familiar ships.

```python
from familiar_bridge import get_job_classes, get_service_specs, get_providers, get_service_map
```

Functions:
- `get_job_classes()` → `dict[str, JobClassInfo]` — reads from `JOB_CLASS_REGISTRY`
- `get_service_specs()` → `dict[str, ServiceInfo]` — reads from `SERVICE_SPECS`
- `get_service_map()` → `dict[str, list[str]]` — reads from `_JOB_SERVICE_MAP`
- `get_providers()` → `list[ProviderInfo]` — reads from `PROVIDERS` registry
- `get_services_for_job_class(key)` → `list[ServiceInfo]` — convenience combo
- `get_version_info()` → familiar + reflection versions
- `summary()` → diagnostic dump (source, counts, keys)

Falls back to static defaults if `familiar-agent` is not installed (ISO build time).
When Familiar adds a new job class, service, or provider, Magic Hat picks it up
automatically on next boot — no wizard changes needed.

## AI Provider Management

Magic Hat supports 4 AI providers simultaneously with auto-routing:

| Provider | Models | Key Source |
|----------|--------|-----------|
| Anthropic | claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5 | console.anthropic.com |
| OpenAI | gpt-4o, gpt-4o-mini | platform.openai.com |
| Google Gemini | gemini-2.5-flash, gemini-2.5-pro | aistudio.google.com (FREE) |
| Ollama (local) | 48+ models, no API key | Runs on server hardware |

```bash
magichat providers status      # Check all provider connectivity
magichat providers configure   # Interactive API key setup
magichat providers test        # Validate all configured keys
magichat providers env         # Show current config (keys masked)
```

Config files:
- `/etc/magichat/providers.env` — API keys + routing config (mode 600)
- `/opt/magichat/scripts/provider-health.sh` — Health check script (--json)
- `/opt/magichat/scripts/configure-providers.sh` — Interactive/non-interactive key setup

Routing: `DEFAULT_PROVIDER=auto` lets Familiar pick the best provider per request.
PHI guard: `FAMILIAR_PHI_LOCAL_ONLY=true` forces sensitive data to Ollama only.

## Dependencies

- `reflection-agent[full]` from PyPI (installed via pip in the image)
- CometBFT binary (Go, installed to /usr/local/bin)
- Fedora Server packages: postgresql-server, redis, nginx, podman, fail2ban, audit, aide
- Document processing: libreoffice-headless (writer/calc/impress), poppler-utils, ghostscript, pandoc, ImageMagick
- OCR: tesseract + English language pack — scanned document text extraction
- Media processing: ffmpeg, sox, mediainfo, perl-Image-ExifTool — audio/video transcoding + metadata
- Fonts: google-noto-sans, liberation-fonts (serif/sans/mono) — required for PDF rendering
- Editors: nano, vim-enhanced
- Hardware monitoring: smartmontools (SMART), nvme-cli, lm-sensors (temp/voltage)
- Crypto: gnupg2 (signing), git-lfs (large model files)
- Tools: tmux, screen, htop, iotop, sysstat, git, jq, curl, wget, lshw, pciutils
