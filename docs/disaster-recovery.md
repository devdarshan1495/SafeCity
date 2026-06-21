# SafeCity — Disaster Recovery Plan

## Overview

This document outlines the disaster recovery (DR) procedures for the SafeCity Public Safety Analytics Platform. The platform is designed for rapid recovery with minimal data loss.

## Recovery Objectives

| Metric | Target | Description |
|--------|--------|-------------|
| **RTO** (Recovery Time Objective) | < 15 minutes | Time to restore service |
| **RPO** (Recovery Point Objective) | < 1 hour | Maximum acceptable data loss |

## Backup Strategy

### What Gets Backed Up

| Component | Method | Frequency | Retention |
|-----------|--------|-----------|-----------|
| K3s etcd | Snapshot via `k3s etcd-snapshot` | On-demand / before changes | 7 backups |
| PostgreSQL | `pg_dump` (custom format) | On-demand / before changes | 7 backups |
| K8s Resources | `kubectl get all -o yaml` | On-demand | 7 backups |

### Backup Storage
- **Location**: S3 bucket `safecity-backups-{account-id}`
- **Encryption**: AES-256 server-side
- **Versioning**: Enabled
- **Lifecycle**: Auto-delete after 30 days

### Running a Backup
```bash
ssh -i ~/Downloads/DevAnalytics.pem ubuntu@<MASTER_IP>
./scripts/backup.sh
```

## Disaster Scenarios & Recovery

### Scenario 1: Pod Failure
**Impact**: Single service degradation
**Self-healing**: Kubernetes automatically reschedules failed pods
**RTO**: ~30 seconds (automatic)

```bash
# Verify recovery
kubectl get pods -n safecity -w
```

### Scenario 2: Node Failure
**Impact**: Workloads on failed node become unavailable
**Recovery**: K3s reschedules pods to remaining nodes

```bash
# Check node status
kubectl get nodes

# If worker is down, workloads move to master
kubectl get pods -n safecity -o wide

# When node recovers, uncordon it
kubectl uncordon <node-name>
```

### Scenario 3: Full Cluster Loss
**Impact**: Complete platform outage
**RTO**: ~15 minutes

```bash
# 1. Re-provision infrastructure
cd terraform
terraform apply

# 2. Wait for K3s bootstrap (5-8 minutes)
ssh -i ~/Downloads/DevAnalytics.pem ubuntu@<NEW_MASTER_IP>
kubectl get nodes  # Wait until both nodes are Ready

# 3. Re-deploy application
kubectl apply -f kubernetes/namespaces.yaml
kubectl apply -f kubernetes/app/
kubectl apply -f kubernetes/monitoring/
kubectl apply -f kubernetes/logging/
kubectl apply -f kubernetes/vault/

# 4. Restore database from backup
./scripts/restore.sh <latest-timestamp>

# 5. Verify
./scripts/health-check.sh <NEW_MASTER_IP>
```

### Scenario 4: Database Corruption
**Impact**: Data integrity issues
**RTO**: ~5 minutes

```bash
# 1. Restore from last known good backup
./scripts/restore.sh <timestamp>

# 2. Verify data integrity
kubectl exec -n safecity $(kubectl get pods -n safecity -l app=postgres -o name) -- \
    psql -U safecity -c "SELECT count(*) FROM incidents;"
```

### Scenario 5: Cyber Attack / Compromise
**Impact**: System integrity
**Procedure**:
1. Isolate affected components (cordon nodes, scale down deployments)
2. Capture forensic data (pod logs, network captures)
3. Rotate all secrets in Vault
4. Rebuild from clean images
5. Restore data from pre-compromise backup

## Testing DR Procedures

Run the chaos testing script to validate recovery:

```bash
# Test all scenarios
./scripts/simulate-outage.sh all

# Test specific scenario
./scripts/simulate-outage.sh pod-kill
./scripts/simulate-outage.sh node-drain
./scripts/simulate-outage.sh cpu-spike
```

## Communication During Incidents

| Severity | Response Time | Escalation |
|----------|--------------|------------|
| Critical | Immediate | All teams notified |
| High | < 15 minutes | On-call engineer |
| Medium | < 1 hour | Next business day |
| Low | < 4 hours | Backlog |
