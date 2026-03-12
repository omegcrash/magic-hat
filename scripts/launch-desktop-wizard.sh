#!/usr/bin/env bash
# Magic Hat — Desktop Setup Wizard Launcher
# Called by magichat-desktop-wizard.service.
# Launches the Kirigami QML wizard; falls back to the web wizard if QML
# runtime is unavailable.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

WIZARD_DIR="/opt/magichat/firstboot/desktop-wizard"
WEB_WIZARD_PORT=8080

# ── Sanity: only run if profile is still unset ────────────────────────────────
if [[ ! -f /etc/magichat/profile.unset ]]; then
    echo "Profile already configured — wizard not needed" >&2
    exit 0
fi

# ── Give the desktop session a moment to settle ───────────────────────────────
sleep 3

# ── Try native Kirigami QML wizard first ─────────────────────────────────────
if command -v qml &>/dev/null && [[ -f "${WIZARD_DIR}/main.qml" ]]; then
    echo "Launching native QML wizard…" >&2
    exec qml \
        -apptype gui \
        "${WIZARD_DIR}/main.qml" \
        2>&1
fi

# ── Fall back: run the web wizard and open Firefox to it ─────────────────────
echo "QML runtime not found — falling back to web wizard on port ${WEB_WIZARD_PORT}" >&2

# Start web wizard in background
/usr/bin/python3 /opt/magichat/firstboot/wizard.py --mode=desktop &
WIZARD_PID=$!

# Wait for it to come up
for i in $(seq 1 10); do
    if curl -sf "http://localhost:${WEB_WIZARD_PORT}/health" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Open in Firefox
if command -v firefox &>/dev/null; then
    firefox --new-window "http://localhost:${WEB_WIZARD_PORT}/" &
elif command -v xdg-open &>/dev/null; then
    xdg-open "http://localhost:${WEB_WIZARD_PORT}/" &
fi

# Wait for web wizard to complete
wait "${WIZARD_PID}"
