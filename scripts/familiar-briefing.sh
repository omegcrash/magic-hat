#!/usr/bin/env bash
# Magic Hat — Familiar AI Daily Briefing Script
# Called by familiar-briefing.service (systemd user timer).
# Fetches the daily briefing from Familiar and sends a KDE notification.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

DASHBOARD_URL="${FAMILIAR_DASHBOARD_URL:-http://localhost:5000}"
TIMEOUT=30

# ── Check Familiar is reachable ───────────────────────────────────────────────
if ! curl -sf --max-time 5 "${DASHBOARD_URL}/health" > /dev/null 2>&1; then
    echo "Familiar dashboard not reachable at ${DASHBOARD_URL} — skipping briefing" >&2
    exit 0
fi

# ── Request briefing ──────────────────────────────────────────────────────────
BRIEFING=$(curl -sf \
    --max-time "${TIMEOUT}" \
    "${DASHBOARD_URL}/api/briefing/daily" 2>/dev/null) || {
    echo "Briefing API call failed — skipping" >&2
    exit 0
}

# Extract summary text (first 200 chars of .summary field)
SUMMARY=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    text = d.get('summary') or d.get('briefing') or d.get('text') or ''
    print(text[:200].replace('\n', ' '))
except Exception:
    print('Good morning! Your daily briefing is ready.')
" <<< "${BRIEFING}")

if [[ -z "${SUMMARY}" ]]; then
    SUMMARY="Good morning! Your daily briefing is ready."
fi

# ── Send KDE notification ─────────────────────────────────────────────────────
if command -v notify-send &>/dev/null; then
    notify-send \
        --app-name="Familiar AI" \
        --icon="familiar" \
        --urgency=normal \
        --expire-time=8000 \
        "🎩 Good morning!" \
        "${SUMMARY}"
fi

# ── Log to journal ────────────────────────────────────────────────────────────
echo "Briefing delivered: ${SUMMARY:0:80}…"
