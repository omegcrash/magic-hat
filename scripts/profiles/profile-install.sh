#!/usr/bin/env bash
# Magic Hat — Profile Dispatcher
# Usage: profile-install.sh <profile_key> [<profile_key> ...]
#
# Reads profile-meta.json, then calls the appropriate sub-script for each
# opt-in profile. Always-on profiles (ai_companion, privacy_suite) are handled
# by the kickstart %post and are not dispatched here.
#
# Copyright (c) 2026 George Scott Foley — MIT License

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${SCRIPT_DIR}"
LOG_FILE="/var/log/magichat/profile-install.log"

mkdir -p /var/log/magichat
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== Magic Hat Profile Install: $(date) ==="

if [[ $# -eq 0 ]]; then
    echo "Usage: profile-install.sh <profile_key> [...]"
    echo "Available opt-in profiles: creative_studio gaming dev_workstation"
    exit 1
fi

for PROFILE_KEY in "$@"; do
    echo "--- Installing profile: ${PROFILE_KEY} ---"

    # Look up script from profile-meta.json
    SCRIPT=$(python3 -c "
import json, sys
meta = json.load(open('${PROFILE_DIR}/profile-meta.json'))
profile = meta['profiles'].get('${PROFILE_KEY}')
if not profile:
    print('NOT_FOUND')
    sys.exit(1)
if profile.get('always_on'):
    print('ALWAYS_ON')
    sys.exit(0)
print(profile.get('script') or 'NO_SCRIPT')
" 2>/dev/null)

    case "${SCRIPT}" in
        NOT_FOUND)
            echo "  ERROR: Unknown profile '${PROFILE_KEY}' — skipping"
            continue
            ;;
        ALWAYS_ON)
            echo "  Profile '${PROFILE_KEY}' is always-on — skipping"
            continue
            ;;
        NO_SCRIPT)
            echo "  Profile '${PROFILE_KEY}' has no install script — skipping"
            continue
            ;;
        *)
            SCRIPT_PATH="${PROFILE_DIR}/${SCRIPT}"
            if [[ -x "${SCRIPT_PATH}" ]]; then
                echo "  Running ${SCRIPT}…"
                bash "${SCRIPT_PATH}"
            else
                echo "  ERROR: Script not found or not executable: ${SCRIPT_PATH}"
            fi
            ;;
    esac

    echo "  Done: ${PROFILE_KEY}"
done

# ── Provision all recorded services via Familiar's ServiceManager ────────────
echo "--- Provisioning desired services ---"
PROVISION_SCRIPT="${SCRIPT_DIR}/../provision-services.py"
if [[ -f "${PROVISION_SCRIPT}" ]]; then
    python3 "${PROVISION_SCRIPT}" || echo "  WARNING: Some services failed to provision"
else
    echo "  WARNING: provision-services.py not found — services recorded but not started"
    echo "  Run: magichat services provision"
fi

echo "=== Profile install complete ==="
