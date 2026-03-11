#!/usr/bin/env bash
# Magic Hat — PostgreSQL Backup Script
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Called by magichat-backup.timer (daily at 03:00)
# Keeps 7 daily + 4 weekly backups, GPG-encrypted if key is configured.

set -euo pipefail

BACKUP_DIR="/var/backups/magichat"
DB_NAME="reflection"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/reflection-${TIMESTAMP}.sql.gz"
RETENTION_DAILY=7
RETENTION_WEEKLY=4

echo "[$(date)] Starting backup of database '${DB_NAME}'..."

# Dump and compress
pg_dump -U reflection "${DB_NAME}" | gzip > "${BACKUP_FILE}"

# Encrypt if GPG key is configured
GPG_RECIPIENT="${MAGICHAT_BACKUP_GPG_KEY:-}"
if [[ -n "${GPG_RECIPIENT}" ]]; then
    gpg --encrypt --recipient "${GPG_RECIPIENT}" --trust-model always "${BACKUP_FILE}"
    rm -f "${BACKUP_FILE}"
    BACKUP_FILE="${BACKUP_FILE}.gpg"
    echo "[$(date)] Backup encrypted with GPG key ${GPG_RECIPIENT}"
fi

# Calculate size
BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "[$(date)] Backup complete: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Rotate: keep RETENTION_DAILY daily backups
DAILY_COUNT=$(ls -1 "${BACKUP_DIR}"/reflection-*.sql.gz* 2>/dev/null | wc -l)
if [[ ${DAILY_COUNT} -gt ${RETENTION_DAILY} ]]; then
    REMOVE_COUNT=$((DAILY_COUNT - RETENTION_DAILY))
    ls -1t "${BACKUP_DIR}"/reflection-*.sql.gz* | tail -n "${REMOVE_COUNT}" | xargs rm -f
    echo "[$(date)] Rotated ${REMOVE_COUNT} old backup(s)"
fi

# Weekly backup (keep on Sundays)
DAY_OF_WEEK=$(date +%u)
if [[ "${DAY_OF_WEEK}" == "7" ]]; then
    WEEKLY_DIR="${BACKUP_DIR}/weekly"
    mkdir -p "${WEEKLY_DIR}"
    cp "${BACKUP_FILE}" "${WEEKLY_DIR}/"
    # Rotate weekly
    WEEKLY_COUNT=$(ls -1 "${WEEKLY_DIR}"/reflection-*.sql.gz* 2>/dev/null | wc -l)
    if [[ ${WEEKLY_COUNT} -gt ${RETENTION_WEEKLY} ]]; then
        REMOVE_COUNT=$((WEEKLY_COUNT - RETENTION_WEEKLY))
        ls -1t "${WEEKLY_DIR}"/reflection-*.sql.gz* | tail -n "${REMOVE_COUNT}" | xargs rm -f
    fi
    echo "[$(date)] Weekly backup saved"
fi

echo "[$(date)] Backup job finished"
