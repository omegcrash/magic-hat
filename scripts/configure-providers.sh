#!/usr/bin/env bash
# Magic Hat — AI Provider Configuration
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Generates /etc/magichat/providers.env from interactive input or arguments.
# This file is sourced by reflection.service and magichat-ollama.service.
#
# Usage:
#   Interactive:  ./configure-providers.sh
#   Non-interactive: ./configure-providers.sh \
#       --anthropic-key sk-ant-xxx \
#       --openai-key sk-xxx \
#       --gemini-key xxx \
#       --default-provider anthropic \
#       --ollama-model llama3.2

set -euo pipefail

ENV_FILE="/etc/magichat/providers.env"
REFLECTION_ENV="/etc/magichat/reflection.env"

# ── Parse args ────────────────────────────────────────────────────────────────

ANTHROPIC_KEY=""
OPENAI_KEY=""
GEMINI_KEY=""
DEFAULT_PROVIDER=""
OLLAMA_MODEL=""
LIGHTWEIGHT_MODEL=""
LIGHTWEIGHT_PROVIDER=""
INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --anthropic-key) ANTHROPIC_KEY="$2"; INTERACTIVE=false; shift 2 ;;
        --openai-key)    OPENAI_KEY="$2"; INTERACTIVE=false; shift 2 ;;
        --gemini-key)    GEMINI_KEY="$2"; INTERACTIVE=false; shift 2 ;;
        --default-provider) DEFAULT_PROVIDER="$2"; shift 2 ;;
        --ollama-model)  OLLAMA_MODEL="$2"; shift 2 ;;
        --lightweight-model) LIGHTWEIGHT_MODEL="$2"; shift 2 ;;
        --lightweight-provider) LIGHTWEIGHT_PROVIDER="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Load existing config ──────────────────────────────────────────────────────

if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    # Preserve existing keys if not overridden
    ANTHROPIC_KEY="${ANTHROPIC_KEY:-${ANTHROPIC_API_KEY:-}}"
    OPENAI_KEY="${OPENAI_KEY:-${OPENAI_API_KEY:-}}"
    GEMINI_KEY="${GEMINI_KEY:-${GEMINI_API_KEY:-}}"
    DEFAULT_PROVIDER="${DEFAULT_PROVIDER:-${DEFAULT_PROVIDER:-}}"
    OLLAMA_MODEL="${OLLAMA_MODEL:-${OLLAMA_MODEL:-}}"
fi

# ── Interactive mode ──────────────────────────────────────────────────────────

if [[ "${INTERACTIVE}" == "true" ]]; then
    echo ""
    echo "  ╔═══════════════════════════════════╗"
    echo "  ║    Magic Hat — AI Providers       ║"
    echo "  ╚═══════════════════════════════════╝"
    echo ""
    echo "  Configure your AI providers. Press Enter to skip any provider."
    echo "  Ollama (local) is always available — no API key needed."
    echo ""

    # Anthropic
    echo "  ── Anthropic (Claude) ──"
    echo "  Models: claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5"
    echo "  Get key: https://console.anthropic.com/settings/keys"
    local_mask=""
    if [[ -n "${ANTHROPIC_KEY}" ]]; then
        local_mask="${ANTHROPIC_KEY:0:8}...${ANTHROPIC_KEY: -4}"
        echo "  Current: ${local_mask}"
    fi
    read -rp "  API key (Enter to keep/skip): " input
    if [[ -n "${input}" ]]; then ANTHROPIC_KEY="${input}"; fi
    echo ""

    # OpenAI
    echo "  ── OpenAI (GPT) ──"
    echo "  Models: gpt-4o, gpt-4o-mini"
    echo "  Get key: https://platform.openai.com/api-keys"
    if [[ -n "${OPENAI_KEY}" ]]; then
        local_mask="${OPENAI_KEY:0:8}...${OPENAI_KEY: -4}"
        echo "  Current: ${local_mask}"
    fi
    read -rp "  API key (Enter to keep/skip): " input
    if [[ -n "${input}" ]]; then OPENAI_KEY="${input}"; fi
    echo ""

    # Gemini
    echo "  ── Google Gemini ──"
    echo "  Models: gemini-2.5-flash, gemini-2.5-pro (1M+ context)"
    echo "  Get key: https://aistudio.google.com/apikey (FREE)"
    if [[ -n "${GEMINI_KEY}" ]]; then
        local_mask="${GEMINI_KEY:0:8}...${GEMINI_KEY: -4}"
        echo "  Current: ${local_mask}"
    fi
    read -rp "  API key (Enter to keep/skip): " input
    if [[ -n "${input}" ]]; then GEMINI_KEY="${input}"; fi
    echo ""

    # Default provider
    echo "  ── Default Provider ──"
    echo "  Options: anthropic, openai, gemini, ollama"
    echo "  (Familiar auto-routes between providers based on task type)"
    read -rp "  Default provider [${DEFAULT_PROVIDER:-auto}]: " input
    if [[ -n "${input}" ]]; then DEFAULT_PROVIDER="${input}"; fi
    echo ""

    # Ollama model
    echo "  ── Ollama (Local) ──"
    echo "  Default model for local inference (no API key required)"
    echo "  Popular: llama3.2, qwen3:14b, mistral, deepseek-r1, phi4"
    read -rp "  Default Ollama model [${OLLAMA_MODEL:-llama3.2}]: " input
    if [[ -n "${input}" ]]; then OLLAMA_MODEL="${input}"; fi
    echo ""
fi

# ── Write config ──────────────────────────────────────────────────────────────

cat > "${ENV_FILE}" << EOF
# Magic Hat — AI Provider Configuration
# Generated: $(date)
# Edit this file or run: magichat providers configure
#
# Familiar supports 4 providers simultaneously with automatic
# routing, fallback, and PHI-safe local inference.

# ── Cloud Providers (API keys) ───────────────────────────────────────────────
# Leave empty to disable a provider. Familiar auto-detects available providers.

# Anthropic (Claude) — https://console.anthropic.com/settings/keys
# Models: claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5
ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-claude-sonnet-4-6}

# OpenAI (GPT) — https://platform.openai.com/api-keys
# Models: gpt-4o, gpt-4o-mini
OPENAI_API_KEY=${OPENAI_KEY}
OPENAI_MODEL=${OPENAI_MODEL:-gpt-4o}

# Google Gemini — https://aistudio.google.com/apikey (FREE tier available)
# Models: gemini-2.5-flash, gemini-2.5-pro (1M+ context window)
GEMINI_API_KEY=${GEMINI_KEY}
GEMINI_MODEL=${GEMINI_MODEL:-gemini-2.5-flash}

# ── Local Provider (Ollama) ──────────────────────────────────────────────────
# Ollama runs locally — no API key, no data leaves your server.
# Managed by magichat-ollama.service.
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=${OLLAMA_MODEL:-llama3.2}

# ── Routing ──────────────────────────────────────────────────────────────────
# Default provider (anthropic / openai / gemini / ollama / auto)
# "auto" = Familiar picks the best available provider per request
DEFAULT_PROVIDER=${DEFAULT_PROVIDER:-auto}

# Lightweight model for background tasks (planning, memory extraction)
# Leave empty for auto-detection (smallest available model)
LIGHTWEIGHT_MODEL=${LIGHTWEIGHT_MODEL:-}
LIGHTWEIGHT_PROVIDER=${LIGHTWEIGHT_PROVIDER:-}

# ── Privacy ──────────────────────────────────────────────────────────────────
# Force PHI/sensitive data to stay local (routes to Ollama only)
# Set to "true" for HIPAA-compliant deployments
FAMILIAR_PHI_LOCAL_ONLY=${FAMILIAR_PHI_LOCAL_ONLY:-false}
EOF

chmod 600 "${ENV_FILE}"
chown magichat:magichat "${ENV_FILE}" 2>/dev/null || true

# Also inject into reflection.env if it exists (Reflection reads from there)
if [[ -f "${REFLECTION_ENV}" ]]; then
    # Remove old provider lines from reflection.env
    for var in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY \
               DEFAULT_PROVIDER OLLAMA_BASE_URL OLLAMA_MODEL \
               LIGHTWEIGHT_MODEL LIGHTWEIGHT_PROVIDER FAMILIAR_PHI_LOCAL_ONLY; do
        sed -i "/^${var}=/d" "${REFLECTION_ENV}" 2>/dev/null || true
    done
    # Append source directive
    if ! grep -q "providers.env" "${REFLECTION_ENV}" 2>/dev/null; then
        echo "" >> "${REFLECTION_ENV}"
        echo "# AI Provider config (managed by magichat providers configure)" >> "${REFLECTION_ENV}"
        echo "# Source: ${ENV_FILE}" >> "${REFLECTION_ENV}"
    fi
fi

echo ""
echo "  Provider configuration saved to ${ENV_FILE}"
echo "  Run 'magichat providers status' to verify connectivity."
echo ""
