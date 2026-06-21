#!/bin/bash
# ── SafeCity — Restore Script ───────────────────────────────────
# Restores from an S3 backup.
# Usage: ./restore.sh <backup-timestamp>
#    eg: ./restore.sh 20260621-143000
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

TIMESTAMP="${1:-}"
S3_BUCKET="safecity-backups-$(aws sts get-caller-identity --query Account --output text)"
AWS_REGION="ap-south-1"
RESTORE_DIR="/tmp/safecity-restore-${TIMESTAMP}"

if [ -z "$TIMESTAMP" ]; then
    echo "Usage: ./restore.sh <backup-timestamp>"
    echo ""
    echo "Available backups:"
    aws s3 ls "s3://${S3_BUCKET}/backups/" --region "$AWS_REGION"
    exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity Restore — from ${TIMESTAMP}"
echo "═══════════════════════════════════════════════════════"

mkdir -p "$RESTORE_DIR"

# ── 1. Download backup from S3 ──────────────────────────────────
echo "[1/3] Downloading backup from S3 …"
aws s3 cp "s3://${S3_BUCKET}/backups/${TIMESTAMP}/" "$RESTORE_DIR/" \
    --recursive --region "$AWS_REGION"

# ── 2. Restore PostgreSQL ──────────────────────────────────────
echo "[2/3] Restoring PostgreSQL database …"
DB_DUMP=$(find "$RESTORE_DIR" -name "*.dump" | head -1)
if [ -n "$DB_DUMP" ]; then
    PG_POD=$(kubectl get pods -n safecity -l app=postgres -o jsonpath='{.items[0].metadata.name}')
    kubectl cp "$DB_DUMP" "safecity/${PG_POD}:/tmp/restore.dump"
    kubectl exec -n safecity "$PG_POD" -- \
        pg_restore -U safecity -d safecity --clean --if-exists /tmp/restore.dump 2>/dev/null || true
    echo "  Database restored."
else
    echo "  No database dump found in backup."
fi

# ── 3. Restart application pods ─────────────────────────────────
echo "[3/3] Restarting application pods …"
kubectl rollout restart deployment -n safecity
kubectl rollout status deployment/safecity-api -n safecity --timeout=120s
kubectl rollout status deployment/safecity-dashboard -n safecity --timeout=120s

# Cleanup
rm -rf "$RESTORE_DIR"

echo "═══════════════════════════════════════════════════════"
echo "  Restore COMPLETE"
echo "═══════════════════════════════════════════════════════"
