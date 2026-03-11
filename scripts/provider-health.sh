#!/usr/bin/env bash
# Magic Hat — AI Provider Health Check
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Checks connectivity and auth for all configured AI providers.
# Called by: magichat providers status, first-boot wizard, monitoring.
# Usage: ./provider-health.sh [--json]

set -euo pipefail

# Load provider config
ENV_FILE="/etc/magichat/providers.env"
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
fi

OUTPUT_JSON="${1:-}"

# ── Provider checks ──────────────────────────────────────────────────────────

check_anthropic() {
    local key="${ANTHROPIC_API_KEY:-}"
    if [[ -z "${key}" ]]; then
        echo "unconfigured"
        return
    fi
    local status
    status=$(curl -sf -o /dev/null -w "%{http_code}" \
        -H "x-api-key: ${key}" \
        -H "anthropic-version: 2023-06-01" \
        "https://api.anthropic.com/v1/models" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
    if [[ "${status}" == "200" ]]; then
        echo "healthy"
    elif [[ "${status}" == "401" ]]; then
        echo "invalid_key"
    elif [[ "${status}" == "000" ]]; then
        echo "unreachable"
    else
        echo "error:${status}"
    fi
}

check_openai() {
    local key="${OPENAI_API_KEY:-}"
    if [[ -z "${key}" ]]; then
        echo "unconfigured"
        return
    fi
    local status
    status=$(curl -sf -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${key}" \
        "https://api.openai.com/v1/models" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
    if [[ "${status}" == "200" ]]; then
        echo "healthy"
    elif [[ "${status}" == "401" ]]; then
        echo "invalid_key"
    elif [[ "${status}" == "000" ]]; then
        echo "unreachable"
    else
        echo "error:${status}"
    fi
}

check_gemini() {
    local key="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
    if [[ -z "${key}" ]]; then
        echo "unconfigured"
        return
    fi
    local status
    status=$(curl -sf -o /dev/null -w "%{http_code}" \
        "https://generativelanguage.googleapis.com/v1beta/models?key=${key}" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
    if [[ "${status}" == "200" ]]; then
        echo "healthy"
    elif [[ "${status}" == "400" || "${status}" == "403" ]]; then
        echo "invalid_key"
    elif [[ "${status}" == "000" ]]; then
        echo "unreachable"
    else
        echo "error:${status}"
    fi
}

check_ollama() {
    local url="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"
    local status
    status=$(curl -sf -o /dev/null -w "%{http_code}" \
        "${url}/api/tags" \
        --connect-timeout 3 --max-time 5 2>/dev/null || echo "000")
    if [[ "${status}" == "200" ]]; then
        local count
        count=$(curl -sf "${url}/api/tags" 2>/dev/null | python3.11 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('models', [])))
except: print('0')
" 2>/dev/null || echo "0")
        echo "healthy:${count}_models"
    elif [[ "${status}" == "000" ]]; then
        echo "unreachable"
    else
        echo "error:${status}"
    fi
}

# ── Run checks ───────────────────────────────────────────────────────────────

ANTHROPIC_STATUS=$(check_anthropic)
OPENAI_STATUS=$(check_openai)
GEMINI_STATUS=$(check_gemini)
OLLAMA_STATUS=$(check_ollama)

# Determine default provider
DEFAULT="${DEFAULT_PROVIDER:-}"
if [[ -z "${DEFAULT}" ]]; then
    if [[ "${ANTHROPIC_STATUS}" == "healthy" ]]; then DEFAULT="anthropic"
    elif [[ "${OPENAI_STATUS}" == "healthy" ]]; then DEFAULT="openai"
    elif [[ "${GEMINI_STATUS}" == "healthy" ]]; then DEFAULT="gemini"
    elif [[ "${OLLAMA_STATUS}" == healthy* ]]; then DEFAULT="ollama"
    else DEFAULT="none"
    fi
fi

# ── Output ───────────────────────────────────────────────────────────────────

if [[ "${OUTPUT_JSON}" == "--json" ]]; then
    cat << EOF
{
    "anthropic": {"status": "${ANTHROPIC_STATUS}", "model": "${ANTHROPIC_MODEL:-claude-sonnet-4-6}"},
    "openai": {"status": "${OPENAI_STATUS}", "model": "${OPENAI_MODEL:-gpt-4o}"},
    "gemini": {"status": "${GEMINI_STATUS}", "model": "${GEMINI_MODEL:-gemini-2.5-flash}"},
    "ollama": {"status": "${OLLAMA_STATUS}", "model": "${OLLAMA_MODEL:-llama3.2}", "base_url": "${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"},
    "default_provider": "${DEFAULT}",
    "lightweight_model": "${LIGHTWEIGHT_MODEL:-}",
    "lightweight_provider": "${LIGHTWEIGHT_PROVIDER:-}"
}
EOF
else
    echo "──────────────────────────────────────"
    echo "  Magic Hat — AI Provider Status"
    echo "──────────────────────────────────────"
    _icon() {
        case "$1" in
            healthy*) echo -e "\033[0;32m●\033[0m" ;;
            unconfigured) echo -e "\033[0;33m○\033[0m" ;;
            *) echo -e "\033[0;31m●\033[0m" ;;
        esac
    }
    echo "  $(_icon "${ANTHROPIC_STATUS}") Anthropic (Claude)    ${ANTHROPIC_STATUS}  [${ANTHROPIC_MODEL:-claude-sonnet-4-6}]"
    echo "  $(_icon "${OPENAI_STATUS}") OpenAI (GPT)          ${OPENAI_STATUS}  [${OPENAI_MODEL:-gpt-4o}]"
    echo "  $(_icon "${GEMINI_STATUS}") Google (Gemini)       ${GEMINI_STATUS}  [${GEMINI_MODEL:-gemini-2.5-flash}]"
    echo "  $(_icon "${OLLAMA_STATUS}") Ollama (Local)        ${OLLAMA_STATUS}  [${OLLAMA_MODEL:-llama3.2}]"
    echo ""
    echo "  Default provider: ${DEFAULT}"
    if [[ -n "${LIGHTWEIGHT_MODEL:-}" ]]; then
        echo "  Lightweight model: ${LIGHTWEIGHT_MODEL} (${LIGHTWEIGHT_PROVIDER:-auto})"
    fi
    echo "──────────────────────────────────────"
fi
