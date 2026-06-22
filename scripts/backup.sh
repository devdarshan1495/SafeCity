#!/bin/bash
set -euo pipefail

S3_BUCKET="$1"
BACKUP_DIR="/tmp/backups/safecity-$(date +%Y%m%d-%H%M%S)"
NAMESPACES="safecity monitoring logging vault"

mkdir -p "$BACKUP_DIR"/{etcd,postgres,kubernetes}

echo "[backup] Exporting Kubernetes resources ..."
for ns in $NAMESPACES; do
    kubectl get all -n "$ns" -o yaml >> "$BACKUP_DIR/kubernetes/resources-$ns.yaml" 2>/dev/null || true
done
kubectl get pvc --all-namespaces -o yaml >> "$BACKUP_DIR/kubernetes/pvc.yaml" 2>/dev/null || true
kubectl get configmap --all-namespaces -o yaml >> "$BACKUP_DIR/kubernetes/configmaps.yaml" 2>/dev/null || true
kubectl get secret --all-namespaces -o yaml >> "$BACKUP_DIR/kubernetes/secrets.yaml" 2>/dev/null || true

echo "[backup] Dumping PostgreSQL ..."
kubectl exec -n safecity postgres-0 -- sh -c 'PGPASSWORD=safecity_prod_pass pg_dump -U safecity safecity' \
    > "$BACKUP_DIR/postgres/dump.sql" 2>/dev/null || echo "[backup] WARNING: Postgres dump failed"

echo "[backup] Snapshotting K3s etcd ..."
k3s etcd-snapshot save --snapshot-dir="$BACKUP_DIR/etcd" 2>/dev/null || echo "[backup] WARNING: etcd snapshot failed"

echo "[backup] Uploading to S3 ..."
aws s3 sync "$BACKUP_DIR" "s3://$S3_BUCKET/safecity-backups/$(basename $BACKUP_DIR)/" --quiet

echo "[backup] Pruning backups older than 7 days ..."
aws s3 ls "s3://$S3_BUCKET/safecity-backups/" | while read -r line; do
    FOLDER=$(echo "$line" | awk '{print $NF}')
    TIMESTAMP=$(echo "$line" | awk '{print $1" "$2}')
    if [ "$(date -d "$TIMESTAMP" +%s 2>/dev/null)" -lt "$(date -d '7 days ago' +%s)" ]; then
        aws s3 rm "s3://$S3_BUCKET/safecity-backups/$FOLDER" --recursive --quiet
        echo "[backup] Pruned: $FOLDER"
    fi
done 2>/dev/null || true

echo "[backup] Complete."
