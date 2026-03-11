"""Magic Hat — Familiar Bridge

Runtime introspection layer that reads from the installed familiar-agent
package. Magic Hat uses this to dynamically discover job classes, services,
providers, and health checks — so the OS layer automatically reflects
whatever Familiar ships, without hardcoding.

Falls back to static defaults if Familiar is not installed (e.g. during
ISO build or minimal installs).

Copyright (c) 2026 George Scott Foley — MIT License
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

logger = logging.getLogger("magichat.bridge")

# ─── Data Types ───────────────────────────────────────────────────────────────

@dataclass
class JobClassInfo:
    """Subset of Familiar's JobClass relevant to the OS layer."""
    key: str
    name: str
    icon: str
    description: str
    services: list[str] = field(default_factory=list)
    recommended_connects: list[str] = field(default_factory=list)


@dataclass
class ServiceInfo:
    """Subset of Familiar's ServiceSpec relevant to container provisioning."""
    key: str
    display_name: str
    description: str
    icon: str
    service_type: str  # "native" or "container"
    image: str = ""
    ports: dict[int, int] = field(default_factory=dict)  # host → container
    env_vars: dict[str, str] = field(default_factory=dict)
    health_check_path: str = ""
    health_check_port: int = 0
    job_classes: list[str] = field(default_factory=list)
    min_ram_gb: float = 0.5


@dataclass
class ProviderInfo:
    """AI provider metadata for the wizard and health checks."""
    key: str  # "anthropic", "openai", "gemini", "ollama"
    display_name: str
    models: list[str] = field(default_factory=list)
    env_key: str = ""  # e.g. "ANTHROPIC_API_KEY"
    health_url: str = ""
    default_model: str = ""
    requires_key: bool = True


# ─── Static Fallbacks ─────────────────────────────────────────────────────────
# Used when Familiar is not installed or import fails.

_FALLBACK_JOB_CLASSES: dict[str, JobClassInfo] = {
    "helper": JobClassInfo(
        key="helper", name="Helper", icon="fa-hat-wizard",
        description="Web search, browsing, shopping, trend tracking, and general research.",
        services=["email_server", "searxng", "joplin"],
    ),
    "social_worker": JobClassInfo(
        key="social_worker", name="Social Worker", icon="fa-hands-holding-heart",
        description="Case management, advocacy, resource navigation, and crisis response.",
        services=["email_server", "joplin", "nextcloud", "gotosocial"],
    ),
    "business_buddy": JobClassInfo(
        key="business_buddy", name="Business Buddy", icon="fa-briefcase",
        description="Productivity, scheduling, and professional communication.",
        services=["email_server", "gitea", "nextcloud", "joplin", "gotosocial"],
    ),
    "nonprofit_director": JobClassInfo(
        key="nonprofit_director", name="Nonprofit Director", icon="fa-building-columns",
        description="Donor management, grant tracking, bookkeeping, and board reporting.",
        services=["email_server", "nextcloud", "joplin", "gitea", "gotosocial"],
    ),
    "chef": JobClassInfo(
        key="chef", name="Chef", icon="fa-utensils",
        description="Recipe management, menu creation, cost tracking, and kitchen operations.",
        services=["email_server", "mealie", "joplin"],
    ),
    "artist": JobClassInfo(
        key="artist", name="Artist", icon="fa-palette",
        description="Studio management, commissions, shows, media library, and sales.",
        services=["email_server", "gitea", "jellyfin", "nextcloud", "gotosocial"],
    ),
}

_FALLBACK_SERVICES: dict[str, ServiceInfo] = {
    "email_server": ServiceInfo(
        key="email_server", display_name="Email Server",
        description="Built-in SMTP/IMAP server", icon="fa-envelope",
        service_type="native", job_classes=["helper", "social_worker", "business_buddy",
                                            "nonprofit_director", "chef", "artist"],
    ),
    "searxng": ServiceInfo(
        key="searxng", display_name="SearXNG",
        description="Privacy-respecting meta search engine", icon="fa-magnifying-glass",
        service_type="container", image="searxng/searxng:latest",
        ports={8888: 8080}, health_check_path="/healthz", health_check_port=8888,
        job_classes=["helper"],
    ),
    "joplin": ServiceInfo(
        key="joplin", display_name="Joplin Server",
        description="Note-taking and knowledge management", icon="fa-note-sticky",
        service_type="container", image="joplin/server:latest",
        ports={22300: 22300}, health_check_path="/api/ping", health_check_port=22300,
        env_vars={"APP_BASE_URL": "http://localhost:22300", "DB_CLIENT": "sqlite3"},
        job_classes=["helper", "social_worker", "business_buddy",
                     "nonprofit_director", "chef", "artist"],
    ),
    "nextcloud": ServiceInfo(
        key="nextcloud", display_name="Nextcloud",
        description="File sync, calendar, and contacts", icon="fa-cloud",
        service_type="container", image="nextcloud:stable",
        ports={8080: 80}, health_check_path="/status.php", health_check_port=8080,
        job_classes=["social_worker", "business_buddy", "nonprofit_director", "artist"],
    ),
    "gitea": ServiceInfo(
        key="gitea", display_name="Gitea",
        description="Self-hosted Git with issue tracking", icon="fa-code-branch",
        service_type="container", image="codeberg.org/forgejo/forgejo:10",
        ports={3000: 3000, 2222: 22}, health_check_path="/api/v1/settings/api",
        health_check_port=3000,
        job_classes=["artist", "business_buddy", "nonprofit_director"],
    ),
    "mealie": ServiceInfo(
        key="mealie", display_name="Mealie",
        description="Recipe manager and meal planner", icon="fa-utensils",
        service_type="container", image="ghcr.io/mealie-recipes/mealie:latest",
        ports={9925: 9000}, health_check_path="/api/app/about", health_check_port=9925,
        env_vars={"ALLOW_SIGNUP": "true", "BASE_URL": "http://localhost:9925"},
        job_classes=["chef"],
    ),
    "jellyfin": ServiceInfo(
        key="jellyfin", display_name="Jellyfin",
        description="Media library and streaming server", icon="fa-film",
        service_type="container", image="jellyfin/jellyfin:latest",
        ports={8096: 8096}, health_check_path="/System/Info/Public",
        health_check_port=8096,
        job_classes=["artist"],
    ),
    "gotosocial": ServiceInfo(
        key="gotosocial", display_name="GoToSocial",
        description="Lightweight Fediverse server", icon="fa-hashtag",
        service_type="container", image="superseriousbusiness/gotosocial:latest",
        ports={8081: 8080}, health_check_path="/api/v1/instance",
        health_check_port=8081,
        env_vars={"GTS_HOST": "localhost:8081", "GTS_DB_TYPE": "sqlite",
                  "GTS_DB_ADDRESS": "/data/sqlite.db"},
        job_classes=["artist", "social_worker", "nonprofit_director", "business_buddy"],
    ),
    "bluesky_pds": ServiceInfo(
        key="bluesky_pds", display_name="Bluesky PDS",
        description="AT Protocol personal data server", icon="fa-butterfly",
        service_type="container", image="ghcr.io/bluesky-social/pds:latest",
        ports={2583: 3000}, health_check_path="/xrpc/_health", health_check_port=2583,
        job_classes=["artist", "social_worker", "nonprofit_director"],
    ),
    "pihole": ServiceInfo(
        key="pihole", display_name="Pi-hole",
        description="Network-wide ad and tracker blocking", icon="fa-shield-halved",
        service_type="container", image="pihole/pihole:latest",
        ports={8053: 80, 53: 53}, health_check_path="/admin/api.php?summary",
        health_check_port=8053, job_classes=[],
    ),
}

_FALLBACK_PROVIDERS: list[ProviderInfo] = [
    ProviderInfo(
        key="anthropic", display_name="Anthropic",
        models=["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"],
        env_key="ANTHROPIC_API_KEY", default_model="claude-sonnet-4-6",
        health_url="https://api.anthropic.com/v1/models",
    ),
    ProviderInfo(
        key="openai", display_name="OpenAI",
        models=["gpt-4o", "gpt-4o-mini"],
        env_key="OPENAI_API_KEY", default_model="gpt-4o",
        health_url="https://api.openai.com/v1/models",
    ),
    ProviderInfo(
        key="gemini", display_name="Google Gemini",
        models=["gemini-2.5-flash", "gemini-2.5-pro"],
        env_key="GEMINI_API_KEY", default_model="gemini-2.5-flash",
        health_url="https://generativelanguage.googleapis.com/v1beta/models",
    ),
    ProviderInfo(
        key="ollama", display_name="Ollama (Local)",
        models=["llama3.2", "qwen3", "mistral", "deepseek-r1", "phi4", "gemma3"],
        env_key="", default_model="llama3.2",
        health_url="http://127.0.0.1:11434/api/tags",
        requires_key=False,
    ),
]


# ─── Bridge Functions ─────────────────────────────────────────────────────────

_familiar_available: bool | None = None


def _check_familiar() -> bool:
    """Check if familiar-agent is importable (cached)."""
    global _familiar_available
    if _familiar_available is None:
        try:
            import familiar  # noqa: F401
            _familiar_available = True
            logger.info("Familiar package detected — using live registries")
        except ImportError:
            _familiar_available = False
            logger.info("Familiar package not found — using static fallbacks")
    return _familiar_available


def get_job_classes() -> dict[str, JobClassInfo]:
    """Return all registered job classes.

    Reads from Familiar's JOB_CLASS_REGISTRY if available,
    otherwise returns static fallbacks.
    """
    if not _check_familiar():
        return dict(_FALLBACK_JOB_CLASSES)

    try:
        from familiar.jobs import JOB_CLASS_REGISTRY
        from familiar.onboard_engine import OnboardingEngine

        # Get service map — it's a class attribute
        svc_map = getattr(OnboardingEngine, "_JOB_SERVICE_MAP", {})

        result = {}
        for key, jc in JOB_CLASS_REGISTRY.items():
            result[key] = JobClassInfo(
                key=jc.key,
                name=jc.name,
                icon=jc.icon,
                description=jc.description,
                services=svc_map.get(key, []),
                recommended_connects=getattr(jc, "recommended_connects", []),
            )
        return result
    except Exception as e:
        logger.warning("Failed to read job classes from Familiar: %s", e)
        return dict(_FALLBACK_JOB_CLASSES)


def get_service_specs() -> dict[str, ServiceInfo]:
    """Return all registered service specifications.

    Reads from Familiar's SERVICE_SPECS if available,
    otherwise returns static fallbacks.
    """
    if not _check_familiar():
        return dict(_FALLBACK_SERVICES)

    try:
        from familiar.services.specs import SERVICE_SPECS

        result = {}
        for key, spec in SERVICE_SPECS.items():
            result[key] = ServiceInfo(
                key=spec.key,
                display_name=spec.display_name,
                description=spec.description,
                icon=spec.icon,
                service_type=spec.service_type.value if hasattr(spec.service_type, "value") else str(spec.service_type),
                image=spec.image,
                ports=dict(spec.ports) if spec.ports else {},
                env_vars=dict(spec.env_vars) if spec.env_vars else {},
                health_check_path=spec.health_check_path,
                health_check_port=spec.health_check_port,
                job_classes=list(spec.job_classes) if spec.job_classes else [],
                min_ram_gb=spec.min_ram_gb,
            )
        return result
    except Exception as e:
        logger.warning("Failed to read service specs from Familiar: %s", e)
        return dict(_FALLBACK_SERVICES)


def get_service_map() -> dict[str, list[str]]:
    """Return job_class_key → [service_keys] mapping.

    Reads from Familiar's OnboardingEngine._JOB_SERVICE_MAP if available.
    """
    if not _check_familiar():
        return {k: v.services for k, v in _FALLBACK_JOB_CLASSES.items()}

    try:
        from familiar.onboard_engine import OnboardingEngine
        return dict(getattr(OnboardingEngine, "_JOB_SERVICE_MAP", {}))
    except Exception as e:
        logger.warning("Failed to read service map from Familiar: %s", e)
        return {k: v.services for k, v in _FALLBACK_JOB_CLASSES.items()}


def get_providers() -> list[ProviderInfo]:
    """Return AI provider metadata for wizard and health checks.

    Reads model names from Familiar's provider registry if available.
    """
    if not _check_familiar():
        return list(_FALLBACK_PROVIDERS)

    try:
        from familiar.core.providers import PROVIDERS, LIGHTWEIGHT_MODELS

        # Build provider info from live registry
        # Group by canonical provider name
        anthropic_models = []
        openai_models = []
        gemini_models = []
        ollama_models = []

        for key in sorted(PROVIDERS.keys()):
            k = key.lower()
            if k.startswith("claude") or k == "anthropic":
                if k not in ("anthropic", "claude") and k not in anthropic_models:
                    anthropic_models.append(k)
            elif k.startswith("gpt") or k == "openai":
                if k not in ("openai", "gpt") and k not in openai_models:
                    openai_models.append(k)
            elif k.startswith("gemini") or k in ("google", "gemini"):
                if k not in ("google", "gemini") and k not in gemini_models:
                    gemini_models.append(k)
            elif k not in ("ollama",):
                # Everything else is an Ollama model alias
                if k not in ollama_models:
                    ollama_models.append(k)

        # Also pull lightweight model names
        lightweight = sorted(LIGHTWEIGHT_MODELS.keys()) if isinstance(LIGHTWEIGHT_MODELS, dict) else []

        return [
            ProviderInfo(
                key="anthropic", display_name="Anthropic",
                models=anthropic_models or ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"],
                env_key="ANTHROPIC_API_KEY", default_model="claude-sonnet-4-6",
                health_url="https://api.anthropic.com/v1/models",
            ),
            ProviderInfo(
                key="openai", display_name="OpenAI",
                models=openai_models or ["gpt-4o", "gpt-4o-mini"],
                env_key="OPENAI_API_KEY", default_model="gpt-4o",
                health_url="https://api.openai.com/v1/models",
            ),
            ProviderInfo(
                key="gemini", display_name="Google Gemini",
                models=gemini_models or ["gemini-2.5-flash", "gemini-2.5-pro"],
                env_key="GEMINI_API_KEY", default_model="gemini-2.5-flash",
                health_url="https://generativelanguage.googleapis.com/v1beta/models",
            ),
            ProviderInfo(
                key="ollama", display_name="Ollama (Local)",
                models=ollama_models[:12] or ["llama3.2", "qwen3", "mistral", "deepseek-r1"],
                env_key="", default_model="llama3.2",
                health_url="http://127.0.0.1:11434/api/tags",
                requires_key=False,
            ),
        ]
    except Exception as e:
        logger.warning("Failed to read providers from Familiar: %s", e)
        return list(_FALLBACK_PROVIDERS)


def get_version_info() -> dict[str, str]:
    """Return Familiar and Reflection version strings."""
    info: dict[str, str] = {"familiar": "not installed", "reflection": "not installed"}
    try:
        import familiar
        info["familiar"] = getattr(familiar, "__version__", "unknown")
    except ImportError:
        pass
    try:
        import reflection
        info["reflection"] = getattr(reflection, "__version__", "unknown")
    except ImportError:
        pass
    return info


# ─── Convenience ──────────────────────────────────────────────────────────────

def get_services_for_job_class(job_class_key: str) -> list[ServiceInfo]:
    """Return the ServiceInfo list for a given job class key."""
    svc_map = get_service_map()
    all_specs = get_service_specs()
    svc_keys = svc_map.get(job_class_key, [])
    return [all_specs[k] for k in svc_keys if k in all_specs]


def summary() -> dict[str, Any]:
    """Return a complete bridge status summary (useful for diagnostics)."""
    versions = get_version_info()
    job_classes = get_job_classes()
    services = get_service_specs()
    providers = get_providers()

    return {
        "source": "familiar" if _check_familiar() else "fallback",
        "versions": versions,
        "job_classes": len(job_classes),
        "job_class_keys": sorted(job_classes.keys()),
        "services": len(services),
        "service_keys": sorted(services.keys()),
        "providers": [p.key for p in providers],
    }
