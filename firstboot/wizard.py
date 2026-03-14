#!/usr/bin/env python3
"""Magic Hat — First-Boot Setup Wizard

A lightweight web wizard that runs once after installation.
Guides the operator through: admin account, job class selection,
GPU detection, model selection, AI providers, domain + TLS.

Runs on port 8080 (before Nginx/TLS is configured).
Self-disables after completion.

No dependencies beyond Python stdlib + subprocess.

Copyright (c) 2026 George Scott Foley — MIT License
"""

from __future__ import annotations

import hashlib
import html
import http.server
import json
import logging
import os
import secrets
import shutil
import socketserver
import subprocess
import sys
import threading
import time
import urllib.parse
from pathlib import Path
from typing import Any

LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 8080
MARKER_FILE = Path("/opt/magichat/.needs-firstboot")
STATE_FILE = Path("/opt/magichat/.wizard-state.json")
ENV_FILE = Path("/etc/magichat/reflection.env")
OLLAMA_URL = "http://127.0.0.1:11434"
BRIDGE_DIR = Path("/opt/magichat/lib")
DESKTOP_MODE_FILE = Path("/etc/magichat/desktop.mode")
PROFILE_UNSET_FILE = Path("/etc/magichat/profile.unset")
SELECTED_PROFILES_FILE = Path("/etc/magichat/selected-profiles")
PROFILE_META_FILE = Path("/opt/magichat/scripts/profiles/profile-meta.json")

logger = logging.getLogger("magichat.wizard")

# ─── State ────────────────────────────────────────────────────────────────────

wizard_state: dict[str, Any] = {
    "step": 1,
    "admin_created": False,
    "gpu": {},
    "model_pulling": False,
    "model_ready": False,
    "model_name": "",
    "model_progress": 0,
    "domain_configured": False,
    "tls_configured": False,
    "complete": False,
}


def is_desktop_mode() -> bool:
    """Return True if this is a desktop installation."""
    return DESKTOP_MODE_FILE.exists()


def load_profile_meta() -> dict:
    """Load profile catalogue from profile-meta.json."""
    if PROFILE_META_FILE.exists():
        try:
            return json.loads(PROFILE_META_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    # Minimal inline fallback
    return {
        "profiles": {
            "ai_companion": {"id": "ai_companion", "label": "AI Companion", "icon": "🤖",
                             "tagline": "Familiar AI assistant, always-on briefings", "always_on": True},
            "privacy_suite": {"id": "privacy_suite", "label": "Privacy Suite", "icon": "🔒",
                              "tagline": "Pi-hole ad blocking, SearXNG search", "always_on": True},
            "creative_studio": {"id": "creative_studio", "label": "Creative Studio", "icon": "🎨",
                                "tagline": "GIMP, Inkscape, Krita, Blender, Kdenlive", "always_on": False},
            "gaming": {"id": "gaming", "label": "Gaming", "icon": "🎮",
                       "tagline": "Steam, Lutris, Proton, MangoHud", "always_on": False},
            "dev_workstation": {"id": "dev_workstation", "label": "Dev Workstation", "icon": "💻",
                                "tagline": "VS Code, Docker, Git tools, language runtimes", "always_on": False},
        }
    }


def save_state() -> None:
    try:
        STATE_FILE.write_text(json.dumps(wizard_state, indent=2))
    except OSError:
        pass


def load_state() -> None:
    global wizard_state
    if STATE_FILE.exists():
        try:
            wizard_state = json.loads(STATE_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            pass


# ─── System Actions ───────────────────────────────────────────────────────────

def detect_gpu() -> dict:
    """Run GPU detection script and return JSON result."""
    script = Path("/opt/magichat/scripts/detect-gpu.sh")
    if not script.exists():
        return {"gpu_vendor": "none", "gpu_model": "", "gpu_vram_mb": 0,
                "driver_status": "not_installed", "recommended_model": "qwen2.5:1.5b"}
    try:
        result = subprocess.run(
            [str(script), "--json"],
            capture_output=True, text=True, timeout=30,
        )
        return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        return {"gpu_vendor": "none", "gpu_model": "", "gpu_vram_mb": 0,
                "driver_status": "not_installed", "recommended_model": "qwen2.5:1.5b"}


def create_admin(email: str, password: str) -> tuple[bool, str]:
    """Create admin user via Reflection CLI."""
    try:
        result = subprocess.run(
            ["/usr/bin/python3.11", "-m", "reflection", "admin", "create-user",
             "--email", email, "--password", password, "--role", "admin"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            return True, "Admin user created"
        return False, result.stderr.strip() or "Failed to create admin user"
    except (subprocess.TimeoutExpired, OSError) as e:
        return False, str(e)


def pull_model(model_name: str) -> None:
    """Pull an Ollama model in a background thread."""
    wizard_state["model_pulling"] = True
    wizard_state["model_name"] = model_name
    wizard_state["model_progress"] = 0
    wizard_state["model_ready"] = False
    save_state()

    def _pull():
        try:
            env = os.environ.copy()
            env["OLLAMA_MODELS"] = "/var/lib/magichat/models"
            proc = subprocess.Popen(
                ["/usr/local/bin/ollama", "pull", model_name],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, env=env,
            )
            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.strip()
                # Parse Ollama progress output
                if "%" in line:
                    try:
                        pct = int(line.split("%")[0].split()[-1])
                        wizard_state["model_progress"] = pct
                    except (ValueError, IndexError):
                        pass
                elif "success" in line.lower():
                    wizard_state["model_progress"] = 100
            proc.wait()
            wizard_state["model_pulling"] = False
            wizard_state["model_ready"] = proc.returncode == 0
            wizard_state["model_progress"] = 100 if proc.returncode == 0 else 0
        except OSError as e:
            logger.error("Model pull failed: %s", e)
            wizard_state["model_pulling"] = False
            wizard_state["model_ready"] = False
        save_state()

    threading.Thread(target=_pull, daemon=True).start()


def configure_domain(domain: str) -> tuple[bool, str]:
    """Configure Nginx server_name and hostname."""
    try:
        # Update Nginx config
        nginx_conf = Path("/etc/nginx/conf.d/reflection.conf")
        if nginx_conf.exists():
            content = nginx_conf.read_text()
            content = content.replace("server_name _;", f"server_name {domain};")
            nginx_conf.write_text(content)

        # Set hostname
        subprocess.run(["hostnamectl", "set-hostname", domain],
                       capture_output=True, timeout=10)

        # Reload Nginx
        subprocess.run(["systemctl", "reload", "nginx"],
                       capture_output=True, timeout=10)

        return True, f"Domain set to {domain}"
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, str(e)


def configure_tls(domain: str, email: str) -> tuple[bool, str]:
    """Request Let's Encrypt TLS certificate."""
    try:
        result = subprocess.run(
            ["certbot", "--nginx", "-d", domain,
             "--non-interactive", "--agree-tos", "-m", email, "--redirect"],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode == 0:
            subprocess.run(["systemctl", "reload", "nginx"],
                           capture_output=True, timeout=10)
            return True, "TLS certificate installed"
        return False, result.stderr.strip() or "Certbot failed"
    except (subprocess.TimeoutExpired, OSError) as e:
        return False, str(e)


def save_providers(anthropic_key: str, openai_key: str, gemini_key: str,
                   default_provider: str) -> tuple[bool, str]:
    """Save provider API keys to /etc/magichat/providers.env."""
    try:
        script = Path("/opt/magichat/scripts/configure-providers.sh")
        if not script.exists():
            # Write directly if script not available
            env_path = Path("/etc/magichat/providers.env")
            env_path.parent.mkdir(parents=True, exist_ok=True)
            env_path.write_text(f"""# Magic Hat — AI Provider Configuration
# Generated by first-boot wizard on {time.strftime('%Y-%m-%d %H:%M')}

ANTHROPIC_API_KEY={anthropic_key}
ANTHROPIC_MODEL=claude-sonnet-4-6

OPENAI_API_KEY={openai_key}
OPENAI_MODEL=gpt-4o

GEMINI_API_KEY={gemini_key}
GEMINI_MODEL=gemini-2.5-flash

OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL={wizard_state.get('model_name', 'llama3.2')}

DEFAULT_PROVIDER={default_provider or 'auto'}
LIGHTWEIGHT_MODEL=
LIGHTWEIGHT_PROVIDER=
FAMILIAR_PHI_LOCAL_ONLY=false
""")
            env_path.chmod(0o600)
            try:
                import pwd
                uid = pwd.getpwnam("magichat").pw_uid
                gid = pwd.getpwnam("magichat").pw_gid
                os.chown(str(env_path), uid, gid)
            except (KeyError, OSError):
                pass
            return True, "Provider configuration saved"

        args = [str(script)]
        if anthropic_key:
            args.extend(["--anthropic-key", anthropic_key])
        if openai_key:
            args.extend(["--openai-key", openai_key])
        if gemini_key:
            args.extend(["--gemini-key", gemini_key])
        if default_provider:
            args.extend(["--default-provider", default_provider])

        result = subprocess.run(args, capture_output=True, text=True, timeout=15)
        return result.returncode == 0, "Provider configuration saved"
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, str(e)


def check_provider_key(provider: str, key: str) -> str:
    """Quick validation of a provider API key. Returns status string."""
    if not key:
        return "skipped"
    try:
        if provider == "anthropic":
            r = subprocess.run(
                ["curl", "-sf", "-o", "/dev/null", "-w", "%{http_code}",
                 "-H", f"x-api-key: {key}",
                 "-H", "anthropic-version: 2023-06-01",
                 "https://api.anthropic.com/v1/models",
                 "--connect-timeout", "5", "--max-time", "10"],
                capture_output=True, text=True, timeout=15)
            return "valid" if r.stdout.strip() == "200" else "invalid"
        elif provider == "openai":
            r = subprocess.run(
                ["curl", "-sf", "-o", "/dev/null", "-w", "%{http_code}",
                 "-H", f"Authorization: Bearer {key}",
                 "https://api.openai.com/v1/models",
                 "--connect-timeout", "5", "--max-time", "10"],
                capture_output=True, text=True, timeout=15)
            return "valid" if r.stdout.strip() == "200" else "invalid"
        elif provider == "gemini":
            r = subprocess.run(
                ["curl", "-sf", "-o", "/dev/null", "-w", "%{http_code}",
                 f"https://generativelanguage.googleapis.com/v1beta/models?key={key}",
                 "--connect-timeout", "5", "--max-time", "10"],
                capture_output=True, text=True, timeout=15)
            return "valid" if r.stdout.strip() == "200" else "invalid"
    except (OSError, subprocess.TimeoutExpired):
        return "error"
    return "unknown"


# ─── Familiar Bridge ──────────────────────────────────────────────────────────
# Dynamically reads job classes, services, and providers from the installed
# familiar-agent package. Falls back to static defaults if not available.

def _load_bridge():
    """Import the bridge module, adding its directory to sys.path if needed."""
    bridge_path = str(BRIDGE_DIR)
    if bridge_path not in sys.path:
        sys.path.insert(0, bridge_path)
    try:
        import familiar_bridge
        return familiar_bridge
    except ImportError:
        logger.warning("familiar_bridge not found at %s — using inline fallbacks", BRIDGE_DIR)
        return None


def _get_job_classes() -> dict:
    """Return job classes as {key: JobClassInfo} from bridge or fallback."""
    bridge = _load_bridge()
    if bridge:
        return bridge.get_job_classes()
    # Minimal inline fallback (should not be reached in production)
    return {}


def _get_service_specs() -> dict:
    """Return service specs as {key: ServiceInfo} from bridge or fallback."""
    bridge = _load_bridge()
    if bridge:
        return bridge.get_service_specs()
    return {}


def _provision_via_service_manager(service_keys: list[str]) -> list[dict]:
    """Provision services via Familiar's ServiceManager.

    Delegates to the provision-services.py script which uses
    Familiar's ServiceManager with full hardened specs (capabilities,
    security settings, volume mounts, health checks).

    Falls back to the bridge-based specs if ServiceManager is unavailable.
    """
    provision_script = Path("/opt/magichat/scripts/provision-services.py")

    if provision_script.exists():
        # Delegate to the provisioner script (uses Familiar's ServiceManager)
        try:
            result = subprocess.run(
                ["python3", str(provision_script), "--json"] + service_keys,
                capture_output=True, text=True, timeout=600)
            if result.returncode == 0 and result.stdout.strip():
                import json as _json
                return _json.loads(result.stdout)
        except (subprocess.TimeoutExpired, OSError, ValueError):
            pass

    # Fallback: minimal provisioning via bridge specs (no hardening)
    service_specs = _get_service_specs()
    runtime = None
    for rt in ("podman", "docker"):
        if shutil.which(rt):
            runtime = rt
            break
    if not runtime:
        return [{"service": "all", "status": "skipped",
                 "message": "No container runtime (podman/docker) found"}]

    results = []
    for svc_key in service_keys:
        spec = service_specs.get(svc_key)
        if not spec:
            continue
        if spec.service_type == "native":
            results.append({"service": spec.display_name, "status": "ok",
                            "message": "Built-in (runs inside Reflection)"})
            continue

        container_name = f"magichat-{svc_key}"
        volume_dir = f"/home/magichat/.familiar/services/{svc_key}"

        try:
            check = subprocess.run(
                [runtime, "ps", "-a", "--filter", f"name={container_name}",
                 "--format", "{{.Status}}"],
                capture_output=True, text=True, timeout=10)
            if check.stdout.strip():
                results.append({"service": spec.display_name, "status": "ok",
                                "message": "Already provisioned"})
                continue

            os.makedirs(volume_dir, exist_ok=True)
            subprocess.run([runtime, "pull", spec.image],
                           capture_output=True, timeout=300)

            run_args = [runtime, "run", "-d", "--name", container_name,
                        "--restart", "unless-stopped", "-v", f"{volume_dir}:/data"]
            for hp, cp in spec.ports.items():
                run_args.extend(["-p", f"127.0.0.1:{hp}:{cp}"])
            for ek, ev in spec.env_vars.items():
                run_args.extend(["-e", f"{ek}={ev}"])
            run_args.append(spec.image)
            result = subprocess.run(run_args, capture_output=True, text=True, timeout=60)

            first_port = next(iter(spec.ports), "?")
            if result.returncode == 0:
                results.append({"service": spec.display_name, "status": "ok",
                                "message": f"Running on port {first_port}"})
            else:
                results.append({"service": spec.display_name, "status": "error",
                                "message": result.stderr.strip()[:120]})
        except (subprocess.TimeoutExpired, OSError) as e:
            results.append({"service": spec.display_name, "status": "error",
                            "message": str(e)[:120]})
    return results


def provision_services(job_class: str) -> list[dict]:
    """Provision recommended services for a job class.

    Delegates to Familiar's ServiceManager which handles hardened container
    specs (capabilities, security settings, volume mounts, health checks).

    Returns a list of {service, status, message} dicts.
    """
    job_classes = _get_job_classes()
    jc = job_classes.get(job_class)
    if not jc:
        return []

    # Also record to desired-services.conf for profile consistency
    try:
        conf = Path("/etc/magichat/desired-services.conf")
        conf.parent.mkdir(parents=True, exist_ok=True)
        existing = set()
        if conf.exists():
            existing = {l.strip() for l in conf.read_text().splitlines() if l.strip()}
        with conf.open("a") as f:
            for svc_key in jc.services:
                if svc_key not in existing:
                    f.write(f"{svc_key}\n")
    except OSError:
        pass

    return _provision_via_service_manager(list(jc.services))


def provision_services_general() -> list[dict]:
    """Provision the essentials for a General Assistant (email + joplin)."""
    return _provision_via_service_manager(["email_server", "joplin"])


def _generate_custom_job_class(description: str) -> str:
    """Generate a custom job class JSON package via Ollama, then install it.

    Returns the job class key if successful, empty string on failure.
    """
    prompt = f"""Create a Familiar AI agent job class configuration based on this description:

"{description}"

Return ONLY valid JSON (no markdown, no explanation) with this exact structure:
{{
    "schema_version": "1.0",
    "type": "job_class",
    "metadata": {{
        "id": "short_snake_case_id",
        "name": "Display Name",
        "version": "1.0.0",
        "author": "Magic Hat Wizard",
        "description": "One sentence description",
        "requires_skills": [],
        "familiar_version": ">=1.15.35"
    }},
    "job_class": {{
        "key": "same_as_metadata_id",
        "name": "Same as metadata name",
        "icon": "fa-icon-name",
        "description": "One sentence description matching metadata",
        "prompt_fragment": "You are a professional [role]. You help with [specific tasks]. You maintain [key qualities].",
        "skill_weights": {{}},
        "species_flavor": {{}},
        "recommended_connects": [],
        "proactive_focus": [],
        "workspace": {{
            "label": "Workspace Name",
            "icon": "fa-icon-name",
            "sections": []
        }}
    }}
}}

Choose an appropriate FontAwesome 6 icon (fa-*). Make the prompt_fragment detailed and professional.
The key and id should be short_snake_case derived from the role name."""

    # Try Ollama first (local, no API key needed)
    try:
        payload = json.dumps({"model": wizard_state.get("model_name", "llama3.2"),
                              "prompt": prompt, "stream": False, "format": "json"})
        result = subprocess.run(
            ["curl", "-sf", "-X", "POST", f"{OLLAMA_URL}/api/generate",
             "-H", "Content-Type: application/json", "-d", payload,
             "--connect-timeout", "5", "--max-time", "60"],
            capture_output=True, text=True, timeout=65)

        if result.returncode == 0 and result.stdout.strip():
            response = json.loads(result.stdout)
            raw = response.get("response", "")
            pkg = json.loads(raw)
            return _install_generated_package(pkg)
    except (json.JSONDecodeError, subprocess.TimeoutExpired, OSError, KeyError):
        pass

    # Try cloud providers if Ollama fails
    for provider, env_key, url, headers_fn, body_fn in [
        ("anthropic", "ANTHROPIC_API_KEY",
         "https://api.anthropic.com/v1/messages",
         lambda k: ["-H", f"x-api-key: {k}", "-H", "anthropic-version: 2023-06-01",
                     "-H", "content-type: application/json"],
         lambda p: json.dumps({"model": "claude-haiku-4-5-20251001", "max_tokens": 2048,
                               "messages": [{"role": "user", "content": p}]})),
        ("openai", "OPENAI_API_KEY",
         "https://api.openai.com/v1/chat/completions",
         lambda k: ["-H", f"Authorization: Bearer {k}", "-H", "content-type: application/json"],
         lambda p: json.dumps({"model": "gpt-4o-mini", "max_tokens": 2048,
                               "messages": [{"role": "user", "content": p}],
                               "response_format": {"type": "json_object"}})),
    ]:
        api_key = os.environ.get(env_key, "")
        if not api_key:
            # Try loading from providers.env
            env_path = Path("/etc/magichat/providers.env")
            if env_path.exists():
                for line in env_path.read_text().splitlines():
                    if line.startswith(f"{env_key}="):
                        api_key = line.split("=", 1)[1].strip()
                        break
        if not api_key:
            continue

        try:
            curl_args = ["curl", "-sf", "-X", "POST", url] + headers_fn(api_key) + [
                "-d", body_fn(prompt), "--connect-timeout", "10", "--max-time", "60"]
            result = subprocess.run(curl_args, capture_output=True, text=True, timeout=65)
            if result.returncode == 0:
                resp = json.loads(result.stdout)
                # Extract content based on provider format
                if provider == "anthropic":
                    raw = resp.get("content", [{}])[0].get("text", "")
                else:
                    raw = resp.get("choices", [{}])[0].get("message", {}).get("content", "")
                # Try to parse as JSON (strip markdown fences if present)
                raw = raw.strip()
                if raw.startswith("```"):
                    raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
                pkg = json.loads(raw)
                return _install_generated_package(pkg)
        except (json.JSONDecodeError, subprocess.TimeoutExpired, OSError, KeyError, IndexError):
            continue

    logger.warning("Failed to generate custom job class — no working LLM provider")
    return ""


def _install_generated_package(pkg: dict) -> str:
    """Write a generated job class package to disk. Returns key or empty string."""
    try:
        meta = pkg.get("metadata", {})
        jc = pkg.get("job_class", {})
        key = jc.get("key", meta.get("id", ""))
        if not key:
            return ""

        # Write to custom job classes directory
        custom_dir = Path("/home/magichat/.familiar/data/custom_job_classes")
        custom_dir.mkdir(parents=True, exist_ok=True)
        pkg_path = custom_dir / f"{key}.json"
        pkg_path.write_text(json.dumps(pkg, indent=2))

        # Try to set ownership
        try:
            import pwd
            uid = pwd.getpwnam("magichat").pw_uid
            gid = pwd.getpwnam("magichat").pw_gid
            os.chown(str(pkg_path), uid, gid)
            os.chown(str(custom_dir), uid, gid)
        except (KeyError, OSError):
            pass

        logger.info("Installed custom job class: %s (%s)", key, meta.get("name", key))
        return key
    except (OSError, KeyError) as e:
        logger.error("Failed to install generated package: %s", e)
        return ""


def _install_community_package(pkg_id: str) -> str:
    """Install a community job class from the cached catalog. Returns key or empty."""
    catalog = wizard_state.get("community_catalog", [])
    for pkg in catalog:
        if pkg.get("id") == pkg_id:
            if pkg.get("installed"):
                # Already installed — just return the key
                return pkg_id

            # Fetch full package from marketplace
            pkg_url = f"https://marketplace.familiar.ai/api/v1/catalog/package/{pkg_id}"
            try:
                result = subprocess.run(
                    ["curl", "-sf", "--connect-timeout", "5", "--max-time", "15", pkg_url],
                    capture_output=True, text=True, timeout=20)
                if result.returncode == 0:
                    full_pkg = json.loads(result.stdout)
                    return _install_generated_package(full_pkg)
            except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
                pass
    return ""


def save_job_class(job_class: str) -> None:
    """Write selected job class to Reflection config so Familiar picks it up."""
    env_path = Path("/etc/magichat/reflection.env")
    if env_path.exists():
        content = env_path.read_text()
        # Remove old job class line if present
        lines = [l for l in content.splitlines() if not l.startswith("FAMILIAR_JOB_CLASS=")]
        lines.append(f"FAMILIAR_JOB_CLASS={job_class}")
        env_path.write_text("\n".join(lines) + "\n")
    else:
        env_path.parent.mkdir(parents=True, exist_ok=True)
        env_path.write_text(f"FAMILIAR_JOB_CLASS={job_class}\n")


def finish_wizard() -> None:
    """Mark wizard as complete, close port, and disable the service."""
    wizard_state["complete"] = True
    save_state()
    # Remove first-boot marker
    MARKER_FILE.unlink(missing_ok=True)
    STATE_FILE.unlink(missing_ok=True)
    # Close wizard port in firewall
    subprocess.run(["firewall-cmd", "--remove-port=8080/tcp", "--permanent"],
                   capture_output=True, timeout=10)
    subprocess.run(["firewall-cmd", "--reload"],
                   capture_output=True, timeout=10)
    # Disable wizard service (stop is deferred so redirect completes)
    subprocess.run(["systemctl", "disable", "magichat-wizard"],
                   capture_output=True, timeout=10)
    # Use a short delay so the HTTP redirect response is sent before we stop
    threading.Thread(target=_deferred_stop, daemon=True).start()


def _deferred_stop() -> None:
    """Stop the wizard service after a brief delay."""
    time.sleep(2)
    subprocess.run(["systemctl", "stop", "magichat-wizard"],
                   capture_output=True, timeout=10)


# ─── HTML Templates ───────────────────────────────────────────────────────────

def render_page(body: str, step: int = 1) -> str:
    steps = [
        (1, "Welcome"),
        (2, "Admin Account"),
        (3, "Job Class"),
        (4, "GPU & Models"),
        (5, "AI Providers"),
        (6, "Domain & TLS"),
        (7, "Complete"),
    ]
    step_html = ""
    for num, label in steps:
        cls = "active" if num == step else ("done" if num < step else "")
        step_html += f'<div class="step {cls}"><span class="num">{num}</span>{label}</div>'

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Magic Hat — Setup</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
       background: #0a0a1a; color: #e0e0e0; min-height: 100vh;
       display: flex; flex-direction: column; align-items: center; }}
.header {{ text-align: center; padding: 2rem 1rem 1rem; }}
.header h1 {{ font-size: 2rem; color: #fff; margin-bottom: 0.25rem; }}
.header p {{ color: #888; font-size: 0.95rem; }}
.steps {{ display: flex; gap: 0.5rem; margin: 1.5rem 0; flex-wrap: wrap; justify-content: center; }}
.step {{ padding: 0.5rem 1rem; border-radius: 2rem; background: #1a1a2e; color: #666;
         font-size: 0.85rem; display: flex; align-items: center; gap: 0.5rem; }}
.step .num {{ width: 1.5rem; height: 1.5rem; border-radius: 50%; background: #333;
              display: flex; align-items: center; justify-content: center;
              font-size: 0.75rem; font-weight: bold; }}
.step.active {{ background: #1e3a5f; color: #7cb3ff; }}
.step.active .num {{ background: #3b82f6; color: #fff; }}
.step.done {{ background: #1a2e1a; color: #6fcf6f; }}
.step.done .num {{ background: #22c55e; color: #fff; }}
.card {{ background: #12122a; border: 1px solid #2a2a4a; border-radius: 12px;
         padding: 2rem; max-width: 540px; width: 90%; margin: 0.5rem auto; }}
.card h2 {{ font-size: 1.3rem; margin-bottom: 1rem; color: #fff; }}
.card p {{ color: #aaa; line-height: 1.6; margin-bottom: 1rem; }}
label {{ display: block; color: #ccc; font-size: 0.85rem; margin-bottom: 0.3rem; margin-top: 0.8rem; }}
input[type=text], input[type=email], input[type=password] {{
    width: 100%; padding: 0.6rem 0.8rem; border-radius: 6px; border: 1px solid #3a3a5a;
    background: #0a0a1a; color: #fff; font-size: 0.95rem; }}
input:focus {{ outline: none; border-color: #3b82f6; box-shadow: 0 0 0 2px rgba(59,130,246,0.2); }}
.btn {{ display: inline-block; padding: 0.7rem 1.5rem; border-radius: 8px; border: none;
        font-size: 0.95rem; cursor: pointer; font-weight: 600; transition: all 0.2s; }}
.btn-primary {{ background: #3b82f6; color: #fff; }}
.btn-primary:hover {{ background: #2563eb; }}
.btn-secondary {{ background: #2a2a4a; color: #ccc; }}
.btn-secondary:hover {{ background: #3a3a5a; }}
.btn-success {{ background: #22c55e; color: #fff; }}
.btn-success:hover {{ background: #16a34a; }}
.actions {{ margin-top: 1.5rem; display: flex; gap: 0.75rem; justify-content: flex-end; }}
.gpu-card {{ background: #1a1a2e; border: 1px solid #2a2a4a; border-radius: 8px;
             padding: 1rem; margin: 1rem 0; }}
.gpu-card .vendor {{ font-size: 1.1rem; font-weight: 600; color: #fff; }}
.gpu-card .detail {{ color: #888; font-size: 0.85rem; margin-top: 0.25rem; }}
.progress {{ width: 100%; height: 8px; background: #1a1a2e; border-radius: 4px; margin: 0.5rem 0; overflow: hidden; }}
.progress-bar {{ height: 100%; background: #3b82f6; border-radius: 4px; transition: width 0.5s ease; }}
.model-tag {{ display: inline-block; padding: 0.3rem 0.8rem; border-radius: 1rem;
              background: #1e3a5f; color: #7cb3ff; font-size: 0.85rem; margin: 0.2rem; }}
.check {{ color: #22c55e; }}
.warn {{ color: #f59e0b; }}
.error-msg {{ color: #ef4444; font-size: 0.85rem; margin-top: 0.5rem; }}
.success-msg {{ color: #22c55e; font-size: 0.85rem; margin-top: 0.5rem; }}
.skip {{ color: #666; font-size: 0.85rem; text-decoration: underline; cursor: pointer; }}
.skip:hover {{ color: #999; }}
</style>
</head>
<body>
<div class="header">
    <h1>Magic Hat</h1>
    <p>Familiar AI Server Platform</p>
</div>
<div class="steps">{step_html}</div>
{body}
</body>
</html>"""


def page_profiles() -> str:
    """Step 0 — Desktop profile selection (desktop mode only)."""
    meta = load_profile_meta()
    profiles = meta.get("profiles", {})
    selected = wizard_state.get("selected_profiles", [])

    cards_html = ""
    for profile_id, profile in profiles.items():
        always_on = profile.get("always_on", False)
        is_selected = always_on or profile_id in selected
        checked = "checked" if is_selected else ""
        disabled = "disabled" if always_on else ""
        lock_badge = ' <span style="font-size:0.7rem;color:#7c8cf8;vertical-align:middle">Always On</span>' if always_on else ""
        card_cls = "profile-card selected" if is_selected else "profile-card"
        icon = html.escape(profile.get("icon", ""))
        label = html.escape(profile.get("label", profile_id))
        tagline = html.escape(profile.get("tagline", ""))
        cards_html += f"""
<label class="{card_cls}" for="prof_{profile_id}">
    <input type="checkbox" id="prof_{profile_id}" name="profiles" value="{profile_id}"
           {checked} {disabled} onchange="toggleCard(this)">
    <span class="prof-icon">{icon}</span>
    <span class="prof-label">{label}{lock_badge}</span>
    <span class="prof-tagline">{tagline}</span>
</label>"""

    return render_page(f"""
<div class="card" style="max-width:560px">
    <h2>Choose Your Setup</h2>
    <p style="color:#9ca3af;margin-bottom:1.5rem">
        AI Companion and Privacy Suite are always included.
        Add optional profiles — you can change these later.
    </p>
    <form method="post" action="/api/profiles">
        <div class="profile-grid">
            {cards_html}
        </div>
        <div class="actions" style="margin-top:2rem">
            <button type="submit" class="btn btn-primary">Continue →</button>
        </div>
    </form>
</div>
<style>
.profile-grid {{ display:grid; grid-template-columns:1fr 1fr; gap:12px; }}
.profile-card {{
    display:flex; flex-direction:column; align-items:center; text-align:center;
    padding:16px 12px; border-radius:10px; border:1px solid #2e3050;
    background:#1e2030; cursor:pointer; transition:border-color 0.15s,background 0.15s;
    user-select:none;
}}
.profile-card input[type=checkbox] {{ display:none; }}
.profile-card.selected {{ border-color:#7c8cf8; background:#252745; }}
.profile-card:hover:not([style*="cursor:default"]) {{ border-color:#5a6adc; }}
.prof-icon {{ font-size:2rem; margin-bottom:6px; }}
.prof-label {{ font-weight:600; color:#eaeaea; font-size:0.95rem; }}
.prof-tagline {{ color:#6b7280; font-size:0.78rem; margin-top:4px; line-height:1.3; }}
</style>
<script>
function toggleCard(cb) {{
    cb.closest('.profile-card').classList.toggle('selected', cb.checked);
}}
</script>""", step=0)


def page_welcome() -> str:
    hostname = os.uname().nodename
    return render_page(f"""
<div class="card">
    <h2>Welcome to Magic Hat</h2>
    <p>This wizard will set up your Familiar AI server in a few steps.
       You'll configure an admin account, detect your GPU, pull a language model,
       and optionally set up a domain with TLS encryption.</p>
    <p style="color:#666; font-size:0.85rem;">
        Hostname: <strong style="color:#ccc">{html.escape(hostname)}</strong>
    </p>
    <div class="actions">
        <a href="/step/2" class="btn btn-primary">Get Started</a>
    </div>
</div>""", step=1)


def page_admin() -> str:
    msg = ""
    if wizard_state.get("admin_created"):
        msg = '<p class="success-msg check">Admin account created.</p>'
    return render_page(f"""
<div class="card">
    <h2>Create Admin Account</h2>
    <p>This account will manage your Reflection platform — tenants, agents, marketplace.</p>
    {msg}
    <form method="POST" action="/api/admin">
        <label for="email">Email</label>
        <input type="email" id="email" name="email" placeholder="admin@example.com" required>
        <label for="password">Password</label>
        <input type="password" id="password" name="password" placeholder="Strong password" required minlength="8">
        <div class="actions">
            <a href="/step/1" class="btn btn-secondary">Back</a>
            <button type="submit" class="btn btn-primary">Create Admin</button>
        </div>
    </form>
</div>""", step=2)


def _render_job_class_card(key: str, jc: Any, service_specs: dict,
                           selected: str) -> str:
    """Render a single job class radio card."""
    is_selected = "border-color:#3b82f6; background:#1e2a4a;" if key == selected else ""
    check_mark = ' <span class="check">&#10003; Selected</span>' if key == selected else ""
    services = getattr(jc, "services", [])
    svc_tags = " ".join(
        f'<span class="model-tag">{html.escape(service_specs[s].display_name if s in service_specs else s)}</span>'
        for s in services
    )
    name = getattr(jc, "name", key)
    desc = getattr(jc, "description", "")
    return f"""
    <label style="display:block; cursor:pointer; margin:0.4rem 0;">
        <div style="background:#1a1a2e; border:1px solid #2a2a4a; border-radius:8px; padding:0.8rem; {is_selected}">
            <div style="display:flex; align-items:center; gap:0.5rem;">
                <input type="radio" name="job_class" value="{html.escape(key)}" {"checked" if key == selected else ""} style="accent-color:#3b82f6;">
                <span style="font-size:1.05rem; font-weight:600; color:#fff;">{html.escape(name)}</span>
                <span style="color:#888; font-size:0.85rem;">— {html.escape(desc[:60])}</span>
                {check_mark}
            </div>
            <p style="color:#999; font-size:0.82rem; margin:0.3rem 0 0.4rem 1.5rem;">{html.escape(desc)}</p>
            <div style="margin-left:1.5rem;">{svc_tags}</div>
        </div>
    </label>"""


def _fetch_community_catalog() -> list[dict]:
    """Fetch community job class catalog from the marketplace.

    Returns a list of {id, name, description, author, version} dicts.
    Cached in wizard_state to avoid re-fetching.
    """
    cached = wizard_state.get("community_catalog")
    if cached is not None:
        return cached

    catalog_url = "https://marketplace.familiar.ai/api/v1/catalog?type=job_class"
    try:
        result = subprocess.run(
            ["curl", "-sf", "--connect-timeout", "5", "--max-time", "10", catalog_url],
            capture_output=True, text=True, timeout=15)
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout)
            packages = data.get("packages", data) if isinstance(data, dict) else data
            if isinstance(packages, list):
                wizard_state["community_catalog"] = packages
                return packages
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        pass

    # Also check if there are any already-installed custom job classes
    custom_dir = Path("/home/magichat/.familiar/data/custom_job_classes")
    installed = []
    if custom_dir.exists():
        for f in custom_dir.glob("*.json"):
            try:
                pkg = json.loads(f.read_text())
                meta = pkg.get("metadata", {})
                installed.append({
                    "id": meta.get("id", f.stem),
                    "name": meta.get("name", f.stem),
                    "description": meta.get("description", ""),
                    "author": meta.get("author", ""),
                    "version": meta.get("version", ""),
                    "installed": True,
                })
            except (json.JSONDecodeError, OSError):
                pass

    wizard_state["community_catalog"] = installed
    return installed


def page_job_class() -> str:
    selected = wizard_state.get("job_class", "")
    provision_results = wizard_state.get("provision_results", [])

    # Build provision status HTML
    prov_html = ""
    if provision_results:
        prov_html = '<div style="margin-top:1rem;">'
        for r in provision_results:
            icon = '<span class="check">&#10003;</span>' if r["status"] == "ok" else '<span class="warn">!</span>'
            prov_html += f'<p style="font-size:0.85rem;">{icon} <strong>{html.escape(r["service"])}</strong> — {html.escape(r["message"])}</p>'
        prov_html += '</div>'

    # Read job classes and service specs from Familiar bridge
    job_classes = _get_job_classes()
    service_specs = _get_service_specs()

    # ── General Assistant (always first) ─────────────────────────────────
    general_selected = "border-color:#3b82f6; background:#1e2a4a;" if selected == "general" else ""
    general_check = ' <span class="check">&#10003; Selected</span>' if selected == "general" else ""
    general_card = f"""
    <label style="display:block; cursor:pointer; margin:0.4rem 0;">
        <div style="background:#1a2e1a; border:1px solid #2a4a2a; border-radius:8px; padding:0.8rem; {general_selected}">
            <div style="display:flex; align-items:center; gap:0.5rem;">
                <input type="radio" name="job_class" value="general" {"checked" if selected == "general" or not selected else ""} style="accent-color:#3b82f6;">
                <span style="font-size:1.05rem; font-weight:600; color:#fff;">General Assistant</span>
                <span style="color:#888; font-size:0.85rem;">— all-purpose AI with essentials</span>
                <span style="background:#1a2e1a; color:#6fcf6f; padding:0.15rem 0.5rem; border-radius:1rem; font-size:0.75rem;">Recommended</span>
                {general_check}
            </div>
            <p style="color:#999; font-size:0.82rem; margin:0.3rem 0 0.4rem 1.5rem;">
                Email, notes, web search, documents, calendar, and tasks.
                All skills available — no specialization. Great starting point.</p>
            <div style="margin-left:1.5rem;">
                <span class="model-tag">Email Server</span>
                <span class="model-tag">Joplin Server</span>
            </div>
        </div>
    </label>"""

    # ── Built-in specializations ─────────────────────────────────────────
    builtin_cards = ""
    for key, jc in job_classes.items():
        builtin_cards += _render_job_class_card(key, jc, service_specs, selected)

    # ── Community / custom roles ─────────────────────────────────────────
    community = _fetch_community_catalog()
    community_html = ""
    if community:
        community_html = """
        <div style="margin-top:1rem; padding-top:0.8rem; border-top:1px solid #2a2a4a;">
            <p style="color:#ccc; font-size:0.9rem; font-weight:600; margin-bottom:0.5rem;">Community Roles</p>
            <p style="color:#888; font-size:0.82rem; margin-bottom:0.5rem;">
                Downloaded from the Familiar marketplace. Install more from the dashboard after setup.</p>"""
        for pkg in community:
            pkg_id = pkg.get("id", "")
            pkg_name = pkg.get("name", pkg_id)
            pkg_desc = pkg.get("description", "Community-created role configuration")
            pkg_author = pkg.get("author", "")
            is_installed = pkg.get("installed", False)
            pkg_selected = "border-color:#3b82f6; background:#1e2a4a;" if selected == f"custom:{pkg_id}" else ""
            pkg_check = ' <span class="check">&#10003; Selected</span>' if selected == f"custom:{pkg_id}" else ""
            installed_badge = '<span style="background:#1a2e1a; color:#6fcf6f; padding:0.15rem 0.5rem; border-radius:1rem; font-size:0.75rem;">Installed</span>' if is_installed else ""
            community_html += f"""
            <label style="display:block; cursor:pointer; margin:0.3rem 0;">
                <div style="background:#1a1a2e; border:1px solid #2a2a4a; border-radius:8px; padding:0.6rem 0.8rem; {pkg_selected}">
                    <div style="display:flex; align-items:center; gap:0.5rem;">
                        <input type="radio" name="job_class" value="custom:{html.escape(pkg_id)}" {"checked" if selected == f"custom:{pkg_id}" else ""} style="accent-color:#3b82f6;">
                        <span style="font-size:0.95rem; font-weight:600; color:#fff;">{html.escape(pkg_name)}</span>
                        {installed_badge}
                        {pkg_check}
                    </div>
                    <p style="color:#999; font-size:0.8rem; margin:0.2rem 0 0 1.5rem;">
                        {html.escape(pkg_desc)}</p>
                    <p style="color:#666; font-size:0.75rem; margin:0.1rem 0 0 1.5rem;">
                        by {html.escape(pkg_author)}</p>
                </div>
            </label>"""
        community_html += "</div>"

    # ── Describe Your Work (custom generation) ───────────────────────────
    custom_html = """
    <div style="margin-top:1rem; padding-top:0.8rem; border-top:1px solid #2a2a4a;">
        <p style="color:#ccc; font-size:0.9rem; font-weight:600; margin-bottom:0.5rem;">Custom Role</p>
        <p style="color:#888; font-size:0.82rem; margin-bottom:0.5rem;">
            Describe what you do and we'll generate a tailored configuration.
            Requires a working AI provider (Ollama or cloud key).</p>
        <label style="display:block; cursor:pointer; margin:0.3rem 0;">
            <div style="background:#1a1a2e; border:1px solid #2a2a4a; border-radius:8px; padding:0.6rem 0.8rem;">
                <div style="display:flex; align-items:center; gap:0.5rem;">
                    <input type="radio" name="job_class" value="custom:generate" style="accent-color:#3b82f6;">
                    <span style="font-size:0.95rem; font-weight:600; color:#fff;">Create Custom Role</span>
                </div>
                <textarea name="custom_description" rows="3"
                    placeholder="e.g. I'm a freelance translator who manages clients, invoices, and deadlines across 4 languages..."
                    style="width:100%; margin:0.5rem 0 0 1.5rem; padding:0.5rem; border-radius:6px; border:1px solid #3a3a5a;
                           background:#0a0a1a; color:#fff; font-size:0.85rem; resize:vertical;
                           font-family:inherit; max-width:calc(100% - 1.5rem);"></textarea>
            </div>
        </label>
    </div>"""

    return render_page(f"""
<div class="card">
    <h2>What Does Your Familiar Do?</h2>
    <p>Pick a role — this determines which workspace, skills, and services are set up for you.
       You can always change it later or create a custom one from the dashboard.</p>
    <p style="color:#888; font-size:0.85rem;">Services shown below each role are auto-provisioned via Podman containers.</p>
    <form method="POST" action="/api/job-class">
        {general_card}
        {builtin_cards}
        {community_html}
        {custom_html}
        {prov_html}
        <div class="actions">
            <a href="/step/2" class="btn btn-secondary">Back</a>
            <button type="submit" class="btn btn-primary">Set Up Role</button>
        </div>
    </form>
</div>""", step=3)


def page_gpu() -> str:
    gpu = wizard_state.get("gpu", {})
    vendor = gpu.get("gpu_vendor", "none")
    model = gpu.get("gpu_model", "None detected")
    vram = gpu.get("gpu_vram_mb", 0)
    driver = gpu.get("driver_status", "not_installed")
    recommended = gpu.get("recommended_model", "qwen2.5:1.5b")

    if vendor == "none":
        gpu_html = """
        <div class="gpu-card">
            <div class="vendor">No GPU Detected</div>
            <div class="detail">Ollama will run in CPU mode. Smaller models recommended.</div>
        </div>"""
    else:
        driver_icon = '<span class="check">installed</span>' if driver == "installed" else f'<span class="warn">{driver}</span>'
        gpu_html = f"""
        <div class="gpu-card">
            <div class="vendor">{html.escape(vendor.upper())}: {html.escape(model)}</div>
            <div class="detail">VRAM: {vram} MB &nbsp;|&nbsp; Driver: {driver_icon}</div>
        </div>"""

    # Model pull status
    model_html = ""
    if wizard_state.get("model_pulling"):
        pct = wizard_state.get("model_progress", 0)
        name = html.escape(wizard_state.get("model_name", ""))
        model_html = f"""
        <p>Pulling <strong>{name}</strong>...</p>
        <div class="progress"><div class="progress-bar" style="width:{pct}%"></div></div>
        <p style="font-size:0.85rem; color:#888">{pct}% complete</p>
        <script>setTimeout(function(){{ location.reload(); }}, 3000);</script>"""
    elif wizard_state.get("model_ready"):
        name = html.escape(wizard_state.get("model_name", ""))
        model_html = f'<p class="success-msg check">Model <strong>{name}</strong> ready!</p>'

    return render_page(f"""
<div class="card">
    <h2>GPU & Language Model</h2>
    <p>We detected your hardware and recommend a model based on available resources.</p>
    {gpu_html}
    <p>Recommended model: <span class="model-tag">{html.escape(recommended)}</span></p>
    {model_html}
    <form method="POST" action="/api/model" style="margin-top:1rem;">
        <label for="model">Model to pull (or accept recommendation)</label>
        <input type="text" id="model" name="model" value="{html.escape(recommended)}" placeholder="e.g. llama3.2, qwen3:14b">
        <div class="actions">
            <a href="/step/3" class="btn btn-secondary">Back</a>
            <button type="submit" class="btn btn-primary">Pull Model</button>
            <a href="/step/5" class="skip">Skip to providers</a>
        </div>
    </form>
</div>""", step=4)


def page_providers() -> str:
    providers = wizard_state.get("providers", {})
    msgs = ""
    for p, status in providers.items():
        if status == "valid":
            msgs += f'<p class="success-msg check">{html.escape(p.title())} key validated.</p>'
        elif status == "invalid":
            msgs += f'<p class="error-msg">{html.escape(p.title())} key is invalid.</p>'
        elif status == "skipped":
            pass  # no message

    return render_page(f"""
<div class="card">
    <h2>AI Providers</h2>
    <p>Magic Hat supports <strong>4 AI providers simultaneously</strong> — cloud and local.
       Familiar auto-routes between them based on task type, privacy requirements, and availability.</p>
    <p style="color:#888; font-size:0.85rem;">All keys are stored in <code>/etc/magichat/providers.env</code> (mode 600). Skip any provider you don't need.</p>
    {msgs}
    <form method="POST" action="/api/providers">
        <div style="background:#1a1a2e; border:1px solid #2a2a4a; border-radius:8px; padding:1rem; margin:0.5rem 0;">
            <div style="display:flex; align-items:center; gap:0.5rem; margin-bottom:0.5rem;">
                <span style="font-size:1.1rem;">Anthropic</span>
                <span class="model-tag">Claude Opus / Sonnet / Haiku</span>
            </div>
            <input type="text" name="anthropic_key" placeholder="sk-ant-..." autocomplete="off" spellcheck="false">
            <div style="color:#666; font-size:0.8rem; margin-top:0.3rem;">
                <a href="https://console.anthropic.com/settings/keys" target="_blank" style="color:#7cb3ff;">Get API key</a> &nbsp;|&nbsp; 200K context
            </div>
        </div>

        <div style="background:#1a1a2e; border:1px solid #2a2a4a; border-radius:8px; padding:1rem; margin:0.5rem 0;">
            <div style="display:flex; align-items:center; gap:0.5rem; margin-bottom:0.5rem;">
                <span style="font-size:1.1rem;">OpenAI</span>
                <span class="model-tag">GPT-4o / GPT-4o-mini</span>
            </div>
            <input type="text" name="openai_key" placeholder="sk-..." autocomplete="off" spellcheck="false">
            <div style="color:#666; font-size:0.8rem; margin-top:0.3rem;">
                <a href="https://platform.openai.com/api-keys" target="_blank" style="color:#7cb3ff;">Get API key</a> &nbsp;|&nbsp; 128K context
            </div>
        </div>

        <div style="background:#1a1a2e; border:1px solid #2a2a4a; border-radius:8px; padding:1rem; margin:0.5rem 0;">
            <div style="display:flex; align-items:center; gap:0.5rem; margin-bottom:0.5rem;">
                <span style="font-size:1.1rem;">Google Gemini</span>
                <span class="model-tag">gemini-2.5-flash / pro</span>
                <span style="background:#1a2e1a; color:#6fcf6f; padding:0.15rem 0.5rem; border-radius:1rem; font-size:0.75rem;">FREE tier</span>
            </div>
            <input type="text" name="gemini_key" placeholder="API key..." autocomplete="off" spellcheck="false">
            <div style="color:#666; font-size:0.8rem; margin-top:0.3rem;">
                <a href="https://aistudio.google.com/apikey" target="_blank" style="color:#7cb3ff;">Get free API key</a> &nbsp;|&nbsp; 1M+ context
            </div>
        </div>

        <div style="background:#1a2e1a; border:1px solid #2a4a2a; border-radius:8px; padding:1rem; margin:0.5rem 0;">
            <div style="display:flex; align-items:center; gap:0.5rem; margin-bottom:0.3rem;">
                <span style="font-size:1.1rem;">Ollama (Local)</span>
                <span class="model-tag">48+ models</span>
                <span style="background:#1a2e1a; color:#6fcf6f; padding:0.15rem 0.5rem; border-radius:1rem; font-size:0.75rem;">Always available</span>
            </div>
            <div style="color:#888; font-size:0.85rem;">No API key needed. Runs on your hardware. Data never leaves the server. Already configured in the previous step.</div>
        </div>

        <label for="default_provider" style="margin-top:1rem;">Default provider</label>
        <input type="text" id="default_provider" name="default_provider" value="auto" placeholder="auto / anthropic / openai / gemini / ollama">
        <p style="color:#666; font-size:0.8rem; margin-top:0.3rem;">
            <code>auto</code> = Familiar picks the best provider per request (recommended)
        </p>

        <div class="actions">
            <a href="/step/4" class="btn btn-secondary">Back</a>
            <button type="submit" class="btn btn-primary">Save &amp; Verify</button>
            <a href="/step/6" class="skip">Skip for now</a>
        </div>
    </form>
</div>""", step=5)


def page_domain() -> str:
    msg = ""
    if wizard_state.get("domain_configured"):
        msg = '<p class="success-msg check">Domain configured.</p>'
    if wizard_state.get("tls_configured"):
        msg += '<p class="success-msg check">TLS certificate installed.</p>'

    return render_page(f"""
<div class="card">
    <h2>Domain & TLS</h2>
    <p>Set a domain name and enable HTTPS with Let's Encrypt.
       This step is optional — you can configure it later with <code>magichat setup</code>.</p>
    {msg}
    <form method="POST" action="/api/domain">
        <label for="domain">Domain name</label>
        <input type="text" id="domain" name="domain" placeholder="ai.example.com">
        <label for="tls_email">Email for Let's Encrypt (optional)</label>
        <input type="email" id="tls_email" name="tls_email" placeholder="admin@example.com">
        <p style="font-size:0.8rem; color:#666; margin-top:0.5rem;">
            Leave email blank to skip TLS. You can set it up later.
        </p>
        <div class="actions">
            <a href="/step/5" class="btn btn-secondary">Back</a>
            <button type="submit" class="btn btn-primary">Configure</button>
            <a href="/step/7" class="skip">Skip for now</a>
        </div>
    </form>
</div>""", step=6)


def page_complete() -> str:
    hostname = os.uname().nodename
    model = wizard_state.get("model_name", "none")
    domain = wizard_state.get("domain", hostname)
    proto = "https" if wizard_state.get("tls_configured") else "http"
    url = f"{proto}://{domain}"
    job_class = wizard_state.get("job_class", "")
    if job_class == "general":
        jc_name = "General Assistant"
    else:
        jc_info = _get_job_classes().get(job_class)
        jc_name = jc_info.name if jc_info else job_class.replace("_", " ").title() or "Not selected"

    # Provisioned services summary
    svc_html = ""
    provision_results = wizard_state.get("provision_results", [])
    if provision_results:
        svc_items = ", ".join(r["service"] for r in provision_results if r["status"] == "ok")
        if svc_items:
            svc_html = f'<p><strong>Services:</strong> {html.escape(svc_items)}</p>'

    return render_page(f"""
<div class="card" style="text-align:center;">
    <h2 style="color:#22c55e;">Setup Complete</h2>
    <p>Your Magic Hat server is ready.</p>
    <div style="background:#1a2e1a; border:1px solid #2a4a2a; border-radius:8px; padding:1.5rem; margin:1.5rem 0; text-align:left;">
        <p><strong>Dashboard:</strong> <a href="{url}" style="color:#7cb3ff;">{url}</a></p>
        <p><strong>Job Class:</strong> {html.escape(jc_name)}</p>
        <p><strong>Model:</strong> {html.escape(model) if model else "None (pull with <code>magichat models pull</code>)"}</p>
        {svc_html}
        <p><strong>Status:</strong> <code>magichat status</code></p>
        <p><strong>Logs:</strong> <code>magichat logs</code></p>
    </div>
    <p style="color:#888; font-size:0.85rem;">
        This wizard will now disable itself. All configuration can be
        managed via the <code>magichat</code> CLI or the Reflection dashboard.
    </p>
    <div style="background:#1a1a2e; border:1px solid #2a2a4a; border-radius:8px; padding:1rem; margin:1rem 0; text-align:left;">
        <p style="color:#ccc; font-size:0.9rem; margin-bottom:0.5rem;"><strong>Want a desktop?</strong></p>
        <p style="color:#888; font-size:0.82rem;">
            Magic Hat can also be your daily-driver desktop OS with GNOME, Firefox,
            LibreOffice, GIMP, and more — all while running your AI services underneath.
        </p>
        <p style="color:#888; font-size:0.82rem; margin-top:0.3rem;">
            Install anytime with: <code>sudo magichat desktop enable</code>
        </p>
    </div>
    <div class="actions" style="justify-content:center;">
        <a href="/api/finish" class="btn btn-success">Finish &amp; Launch Dashboard</a>
    </div>
</div>""", step=7)


# ─── HTTP Handler ─────────────────────────────────────────────────────────────

class WizardHandler(http.server.BaseHTTPRequestHandler):
    """Handles all wizard HTTP requests — pages and API actions."""

    def log_message(self, format: str, *args: Any) -> None:
        logger.info(format, *args)

    def _respond(self, code: int, content: str, content_type: str = "text/html") -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content.encode())

    def _redirect(self, url: str) -> None:
        self.send_response(302)
        self.send_header("Location", url)
        self.end_headers()

    def _read_form(self) -> dict[str, str]:
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode()
        return dict(urllib.parse.parse_qsl(body))

    def do_GET(self) -> None:
        path = self.path.split("?")[0]

        if path == "/" or path == "/step/1":
            # Desktop mode: redirect to profile selection first
            if is_desktop_mode() and PROFILE_UNSET_FILE.exists() and not wizard_state.get("profiles_selected"):
                self._redirect("/step/0")
                return
            self._respond(200, page_welcome())
        elif path == "/step/0":
            # Desktop profile selection (no-op on server installs)
            if is_desktop_mode():
                self._respond(200, page_profiles())
            else:
                self._redirect("/step/1")
        elif path == "/step/2":
            self._respond(200, page_admin())
        elif path == "/step/3":
            self._respond(200, page_job_class())
        elif path == "/step/4":
            # Auto-detect GPU on first visit
            if not wizard_state.get("gpu"):
                wizard_state["gpu"] = detect_gpu()
                save_state()
            self._respond(200, page_gpu())
        elif path == "/step/5":
            self._respond(200, page_providers())
        elif path == "/step/6":
            self._respond(200, page_domain())
        elif path == "/step/7":
            self._respond(200, page_complete())
        elif path == "/api/finish":
            finish_wizard()
            hostname = os.uname().nodename
            domain = wizard_state.get("domain", hostname)
            proto = "https" if wizard_state.get("tls_configured") else "http"
            self._redirect(f"{proto}://{domain}")
        elif path == "/api/state":
            self._respond(200, json.dumps(wizard_state, indent=2), "application/json")
        elif path == "/health":
            self._respond(200, '{"status":"ok"}', "application/json")
        else:
            self._respond(404, render_page('<div class="card"><h2>Not Found</h2></div>'))

    def do_POST(self) -> None:
        path = self.path
        form = self._read_form()

        if path == "/api/profiles":
            # Collect selected opt-in profiles (always-on are implicit)
            raw = form.get("profiles", "")
            selected = [p.strip() for p in (raw if isinstance(raw, list) else [raw]) if p.strip()]

            # Write to /etc/magichat/selected-profiles (one key per line)
            try:
                SELECTED_PROFILES_FILE.parent.mkdir(parents=True, exist_ok=True)
                SELECTED_PROFILES_FILE.write_text("\n".join(selected) + "\n")
            except OSError:
                pass

            wizard_state["selected_profiles"] = selected
            wizard_state["profiles_selected"] = True
            save_state()
            self._redirect("/step/1")

        elif path == "/api/admin":
            email = form.get("email", "").strip()
            password = form.get("password", "")
            if not email or not password:
                self._respond(400, render_page(
                    '<div class="card"><h2>Error</h2><p>Email and password required.</p>'
                    '<div class="actions"><a href="/step/2" class="btn btn-primary">Back</a></div></div>',
                    step=2))
                return
            ok, msg = create_admin(email, password)
            if ok:
                wizard_state["admin_created"] = True
                wizard_state["admin_email"] = email
                save_state()
                self._redirect("/step/3")  # → Job Class
            else:
                self._respond(200, render_page(
                    f'<div class="card"><h2>Admin Setup</h2>'
                    f'<p class="error-msg">{html.escape(msg)}</p>'
                    f'<div class="actions"><a href="/step/2" class="btn btn-primary">Try Again</a></div></div>',
                    step=2))

        elif path == "/api/job-class":
            job_class = form.get("job_class", "").strip()
            custom_desc = form.get("custom_description", "").strip()

            if job_class == "custom:generate" and custom_desc:
                # Generate a custom job class via LLM
                generated = _generate_custom_job_class(custom_desc)
                if generated:
                    wizard_state["job_class"] = generated
                    save_job_class(generated)
                    results = provision_services(generated)
                    wizard_state["provision_results"] = results
                    save_state()
                    self._redirect("/step/3")  # Show results on same page
                    return
                # If generation fails, fall through to default
                job_class = "general"

            elif job_class and job_class.startswith("custom:"):
                # Community package — install if not already, then activate
                pkg_id = job_class[7:]
                installed_key = _install_community_package(pkg_id)
                if installed_key:
                    wizard_state["job_class"] = installed_key
                    save_job_class(installed_key)
                    results = provision_services(installed_key)
                    wizard_state["provision_results"] = results
                    save_state()
                    self._redirect("/step/4")
                    return
                # If install fails, fall to general
                job_class = "general"

            if job_class == "general":
                # General Assistant — email + joplin, no job_class specialization
                wizard_state["job_class"] = "general"
                save_job_class("")  # Empty = general-purpose mode in Familiar
                results = provision_services_general()
                wizard_state["provision_results"] = results
                save_state()
            elif job_class and job_class in _get_job_classes():
                wizard_state["job_class"] = job_class
                save_job_class(job_class)
                results = provision_services(job_class)
                wizard_state["provision_results"] = results
                save_state()

            self._redirect("/step/4")  # → GPU & Models

        elif path == "/api/model":
            model = form.get("model", "").strip()
            if model:
                pull_model(model)
            self._redirect("/step/4")  # stay on GPU page for progress

        elif path == "/api/providers":
            anthropic_key = form.get("anthropic_key", "").strip()
            openai_key = form.get("openai_key", "").strip()
            gemini_key = form.get("gemini_key", "").strip()
            default_provider = form.get("default_provider", "auto").strip()

            # Validate keys
            statuses = {}
            for name, key in [("anthropic", anthropic_key), ("openai", openai_key), ("gemini", gemini_key)]:
                statuses[name] = check_provider_key(name, key)
            wizard_state["providers"] = statuses

            # Save configuration
            ok, msg = save_providers(anthropic_key, openai_key, gemini_key, default_provider)
            wizard_state["providers_configured"] = ok
            save_state()

            # Restart Reflection to pick up new provider env
            subprocess.run(["systemctl", "restart", "reflection"],
                           capture_output=True, timeout=30)

            self._redirect("/step/6")  # → Domain & TLS

        elif path == "/api/domain":
            domain = form.get("domain", "").strip()
            tls_email = form.get("tls_email", "").strip()

            if not domain:
                self._redirect("/step/7")
                return

            ok, msg = configure_domain(domain)
            if ok:
                wizard_state["domain_configured"] = True
                wizard_state["domain"] = domain
                save_state()

                if tls_email:
                    ok_tls, msg_tls = configure_tls(domain, tls_email)
                    wizard_state["tls_configured"] = ok_tls
                    save_state()

            self._redirect("/step/7")  # → Complete

        else:
            self._respond(404, '{"error":"not found"}', "application/json")


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Magic Hat First-Boot Wizard")
    parser.add_argument(
        "--mode",
        choices=["server", "desktop", "auto"],
        default="auto",
        help=(
            "Wizard mode: 'server' (headless web wizard), 'desktop' (desktop ISO "
            "web fallback), 'auto' (detect from /etc/magichat/desktop.mode). "
            "The native QML wizard is preferred for desktop; this runs as fallback."
        ),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=LISTEN_PORT,
        help="Port to listen on (default: %(default)s)",
    )
    parser.add_argument(
        "--skip-marker-check",
        action="store_true",
        help="Skip the MARKER_FILE existence check (for CI testing)",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )

    # Resolve mode
    effective_mode = args.mode
    if effective_mode == "auto":
        effective_mode = "desktop" if DESKTOP_MODE_FILE.exists() else "server"
    logger.info("Wizard mode: %s", effective_mode)

    # Check if first-boot is needed
    if not args.skip_marker_check and not MARKER_FILE.exists():
        logger.info("No first-boot marker found — wizard not needed")
        sys.exit(0)

    load_state()

    port = args.port
    logger.info("Starting Magic Hat First-Boot Wizard on port %d", port)
    if effective_mode == "server":
        logger.info("Open http://<server-ip>:%d in your browser", port)
    else:
        logger.info("Desktop mode — web fallback wizard running on port %d", port)

    server = socketserver.TCPServer((LISTEN_HOST, port), WizardHandler)
    server.allow_reuse_address = True

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Wizard stopped")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
