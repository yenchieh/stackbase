#!/bin/bash
#
# stackbase Postgres restore — pulls a named dump from MinIO and restores it into
# the in-cluster Postgres pod. Destructive: drops existing objects (--clean).
# Runs from an operator workstation with `mc` + `kubectl` access to the cluster.
#
# Prod (default): current kube-context = the server. Local: run with
#   KUBECTL="microk8s kubectl"  to target the local cluster.
#
# MinIO creds come from the environment (never hardcode secrets in the repo);
# use the same values you put in secrets.env:
#   MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY

set -u

if [ $# -ne 1 ]; then
  echo "Usage: MINIO_ENDPOINT=... MINIO_ACCESS_KEY=... MINIO_SECRET_KEY=... $0 <backup-filename>"
  echo "  e.g. $0 stackbase-20260708_000000.sql"
  echo ""
  echo "List available backups:"
  echo "  mc alias set stackbase_minio \"\$MINIO_ENDPOINT\" \"\$MINIO_ACCESS_KEY\" \"\$MINIO_SECRET_KEY\""
  echo "  mc ls stackbase_minio/stackbase-backup/"
  exit 2
fi

FILENAME="$1"

KUBECTL=${KUBECTL:-kubectl}
NAMESPACE=${NAMESPACE:-"stackbase"}
POSTGRES_POD=${POSTGRES_POD:-"postgres-0"}
POSTGRES_CTR=${POSTGRES_CTR:-"postgres"}
DB_USER=${DB_USER:-"stackbase"}
DB_NAME=${DB_NAME:-"stackbase"}
BACKUP_DIR=${BACKUP_DIR:-"/tmp"}

MINIO_ALIAS=${MINIO_ALIAS:-"stackbase_minio"}
MINIO_ENDPOINT=${MINIO_ENDPOINT:?set MINIO_ENDPOINT}
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:?set MINIO_ACCESS_KEY}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:?set MINIO_SECRET_KEY}
MINIO_BUCKET=${MINIO_BUCKET:-"stackbase-backup"}

HOST_FILE="$BACKUP_DIR/$FILENAME"
CONTAINER_FILE="/tmp/$FILENAME"

mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" > /dev/null

echo "Downloading $FILENAME from MinIO..."
if ! mc cp "$MINIO_ALIAS/$MINIO_BUCKET/$FILENAME" "$HOST_FILE"; then
  echo "ERROR: could not download $FILENAME from MinIO"
  exit 1
fi

FILESIZE=$(du -h "$HOST_FILE" | cut -f1)
echo ""
echo "About to restore $HOST_FILE ($FILESIZE) into pod '$POSTGRES_POD' (ns '$NAMESPACE'), DB '$DB_NAME'."
echo "This will DROP existing objects (--clean --if-exists)."
read -p "Continue? [y/N] " CONFIRM
case "$CONFIRM" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; rm -f "$HOST_FILE"; exit 0 ;;
esac

echo "Copying dump into pod..."
if ! $KUBECTL cp "$HOST_FILE" "$NAMESPACE/$POSTGRES_POD:$CONTAINER_FILE" -c "$POSTGRES_CTR"; then
  echo "ERROR: kubectl cp failed"
  rm -f "$HOST_FILE"
  exit 1
fi

echo "Running pg_restore..."
$KUBECTL -n "$NAMESPACE" exec "$POSTGRES_POD" -c "$POSTGRES_CTR" -- \
  env PGPASSWORD="$($KUBECTL -n "$NAMESPACE" get secret app-secrets -o jsonpath='{.data.postgres-password}' | base64 -d)" \
  pg_restore -U "$DB_USER" -d "$DB_NAME" --clean --if-exists -v "$CONTAINER_FILE"
RESTORE_RC=$?

echo "Cleaning up temp files..."
$KUBECTL -n "$NAMESPACE" exec "$POSTGRES_POD" -c "$POSTGRES_CTR" -- rm -f "$CONTAINER_FILE"
rm -f "$HOST_FILE"

if [ $RESTORE_RC -ne 0 ]; then
  echo "pg_restore exited with $RESTORE_RC (some errors are expected on --clean when objects don't yet exist; inspect output)."
  exit $RESTORE_RC
fi

echo "Restore complete."
