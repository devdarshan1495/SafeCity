#!/bin/bash
# ── SafeCity — Backup Script ────────────────────────────────────
# Backs up K3s etcd + PostgreSQL to S3.
# Usage: ./backup.sh
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/tmp/safecity-backup-${TIMESTAMP}"
S3_BUCKET="safecity-backups-$(aws sts get-caller-identity --query Account --output text)"
AWS_REGION="ap-south-1"

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity Backup — ${TIMESTAMP}"
echo "═══════════════════════════════════════════════════════"

mkdir -p "$BACKUP_DIR"

# ── 1. K3s etcd snapshot ────────────────────────────────────────
echo "[1/3] Creating K3s etcd snapshot …"
sudo k3s etcd-snapshot save --name "safecity-${TIMESTAMP}" 2>/dev/null || \
    echo "  Skipped: K3s etcd snapshot (may not be available on agent nodes)"

# Copy snapshot if exists
SNAPSHOT_DIR="/var/lib/rancher/k3s/server/db/snapshots"
if [ -d "$SNAPSHOT_DIR" ]; then
    cp "$SNAPSHOT_DIR"/safecity-${TIMESTAMP}* "$BACKUP_DIR/" 2>/dev/null || true
fi

# ── 2. PostgreSQL dump ──────────────────────────────────────────
echo "[2/3] Dumping PostgreSQL database …"
PG_POD=$(kubectl get pods -n safecity -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$PG_POD" ]; then
    kubectl exec -n safecity "$PG_POD" -- \
        pg_dump -U safecity -d safecity --format=custom \
        > "$BACKUP_DIR/safecity-db-${TIMESTAMP}.dump"
    echo "  Database dump created."
else
    echo "  Skipped: PostgreSQL pod not found."
fi

# ── 3. K8s manifests snapshot ───────────────────────────────────
echo "[3/3] Exporting current K8s resource state …"
for ns in safecity monitoring logging vault; do
    kubectl get all -n "$ns" -o yaml > "$BACKUP_DIR/k8s-resources-${ns}.yaml" 2>/dev/null || true
done

# ── Upload to S3 ───────────────────────────────────────────────
echo "Uploading to s3://${S3_BUCKET}/backups/${TIMESTAMP}/ …"
aws s3 cp "$BACKUP_DIR" "s3://${S3_BUCKET}/backups/${TIMESTAMP}/" \
    --recursive --region "$AWS_REGION"

# ── Cleanup old backups (keep last 7) ──────────────────────────
echo "Cleaning up old backups (keeping last 7) …"
BACKUP_DIRS=$(aws s3 ls "s3://${S3_BUCKET}/backups/" --region "$AWS_REGION" | awk '{print $2}' | sort -r | tail -n +8)
for dir in $BACKUP_DIRS; do
    echo "  Deleting old backup: ${dir}"
    aws s3 rm "s3://${S3_BUCKET}/backups/${dir}" --recursive --region "$AWS_REGION"
done

# Cleanup local temp
rm -rf "$BACKUP_DIR"

echo "═══════════════════════════════════════════════════════"
echo "  Backup COMPLETE — s3://${S3_BUCKET}/backups/${TIMESTAMP}/"
echo "═══════════════════════════════════════════════════════"
