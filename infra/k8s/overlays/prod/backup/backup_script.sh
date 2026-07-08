#!/bin/bash
set -euo pipefail
#
# stackbase Postgres backup — runs inside the prod-only CronJob `postgres-backup`.
# Connects to the in-cluster `postgres` host over TCP, uploads a custom-format
# pg_dump to MinIO (any S3-compatible store), prunes dumps older than
# RETENTION_DAYS, and Discord-alerts on failure. Restore with restore_script.sh.
#
# All MinIO/Discord config is OPTIONAL secret keys: an unconfigured deploy runs,
# fails the alias step, and (silently, if no webhook) records a failed Job —
# rather than wedging the pod in CreateContainerConfigError. Configure the keys
# in secrets.env (see secrets.env.example) before relying on backups.

DB_HOST=${DB_HOST:-"postgres"}
DB_PORT=${DB_PORT:-"5432"}
DB_USER=${DB_USER:-"stackbase"}
DB_NAME=${DB_NAME:-"stackbase"}
BACKUP_DIR=${BACKUP_DIR:-"/tmp"}
DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/$DB_NAME-$DATE.sql"
trap 'rm -f "$BACKUP_FILE"' EXIT

MINIO_ALIAS=${MINIO_ALIAS:-"stackbase_minio"}
MINIO_ENDPOINT=${MINIO_ENDPOINT:-""}
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-""}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:-""}
MINIO_BUCKET=${MINIO_BUCKET:-"stackbase-backup"}
RETENTION_DAYS=${RETENTION_DAYS:-"30"}

DISCORD_WEBHOOK=${DISCORD_WEBHOOK:-""}

notify_discord() {
  local message="$1"
  if [ -n "$DISCORD_WEBHOOK" ]; then
    curl -s -H "Content-Type: application/json" \
      -d "{\"content\":\"$message\"}" \
      "$DISCORD_WEBHOOK" > /dev/null 2>&1 || true
  fi
}

mkdir -p "$BACKUP_DIR"

if ! PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -F c -b "$DB_NAME" > "$BACKUP_FILE"; then
  notify_discord "🔴 **[stackbase] Postgres backup failed** — pg_dump error at $DATE. Host: $DB_HOST, DB: $DB_NAME"
  exit 1
fi

if [ ! -s "$BACKUP_FILE" ]; then
  notify_discord "🔴 **[stackbase] Postgres backup failed** — pg_dump produced an empty dump at $DATE. Host: $DB_HOST, DB: $DB_NAME"
  exit 1
fi

if ! mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" > /dev/null; then
  notify_discord "🔴 **[stackbase] Postgres backup failed** — MinIO alias config error at $DATE. Endpoint: $MINIO_ENDPOINT (is MinIO configured in secrets.env?)"
  exit 1
fi
mc mb --ignore-existing "$MINIO_ALIAS/$MINIO_BUCKET" > /dev/null 2>&1 || true
if ! mc cp "$BACKUP_FILE" "$MINIO_ALIAS/$MINIO_BUCKET/"; then
  FILESIZE=$(du -h "$BACKUP_FILE" 2>/dev/null | cut -f1)
  notify_discord "🔴 **[stackbase] Postgres backup failed** — MinIO upload error at $DATE. File: $(basename "$BACKUP_FILE") ($FILESIZE). pg_dump succeeded but the upload failed."
  exit 1
fi

# ponytail: best-effort prune — the backup already uploaded, so a prune failure
# is a warning, not a backup failure. Drop this if the bucket gets a lifecycle rule.
if ! mc rm --recursive --force --older-than "${RETENTION_DAYS}d" "$MINIO_ALIAS/$MINIO_BUCKET/" > /dev/null 2>&1; then
  notify_discord "🟡 **[stackbase] Backup retention prune failed** at $DATE (backup itself succeeded). Bucket: $MINIO_BUCKET, keep: ${RETENTION_DAYS}d"
fi

echo "[$DATE] backup OK → $MINIO_ALIAS/$MINIO_BUCKET/$(basename "$BACKUP_FILE")"
