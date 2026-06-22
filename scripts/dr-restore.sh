#!/bin/bash
set -euo pipefail

S3_BUCKET="$1"

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity DR Restore — $(date)"
echo "═══════════════════════════════════════════════════════"

LATEST=$(aws s3 ls "s3://$S3_BUCKET/safecity-backups/" | sort | tail -1 | awk '{print $NF}')
if [ -z "$LATEST" ]; then
    echo "No backups found in s3://$S3_BUCKET/safecity-backups/"
    exit 1
fi
echo "Restoring from: $LATEST"

RESTORE_DIR="/tmp/dr-restore"
mkdir -p "$RESTORE_DIR"
aws s3 sync "s3://$S3_BUCKET/safecity-backups/$LATEST" "$RESTORE_DIR" --quiet

if [ -f "$RESTORE_DIR/postgres/dump.sql" ]; then
    echo "[DR] Restoring PostgreSQL ..."
    until kubectl get pod -n safecity postgres-0 -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running; do
        sleep 5
    done
    kubectl exec -n safecity postgres-0 -- sh -c 'PGPASSWORD=safecity_prod_pass psql -U safecity -d postgres -c "DROP DATABASE IF EXISTS safecity;" 2>/dev/null; PGPASSWORD=safecity_prod_pass psql -U safecity -d postgres -c "CREATE DATABASE safecity;" 2>/dev/null'
    kubectl exec -n safecity postgres-0 -i -- sh -c 'PGPASSWORD=safecity_prod_pass psql -U safecity safecity' < "$RESTORE_DIR/postgres/dump.sql"
    echo "[DR] PostgreSQL restored."
else
    echo "[DR] No PostgreSQL backup found."
fi

if [ -d "$RESTORE_DIR/kubernetes" ]; then
    echo "[DR] Re-applying Kubernetes resources ..."
    for f in "$RESTORE_DIR/kubernetes/"*.yaml; do
        [ -f "$f" ] && kubectl apply -f "$f" 2>/dev/null || true
    done
    echo "[DR] Kubernetes resources applied."
fi

echo "DR Restore COMPLETE."
