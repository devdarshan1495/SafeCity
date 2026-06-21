# SafeCity — Architecture Documentation

## System Overview

SafeCity is a cloud-native urban public safety analytics platform built to demonstrate a comprehensive DevOps ecosystem. The platform processes real-time surveillance, emergency response, and IoT sensor data to provide incident management, threat detection, and operational analytics.

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                      AWS ap-south-1 (Mumbai)                     │
│                                                                  │
│  ┌─────────────────── VPC: 10.0.0.0/16 ──────────────────────┐  │
│  │                                                            │  │
│  │  ┌─── Public Subnet 1 (10.0.1.0/24) ──────────────────┐   │  │
│  │  │                                                     │   │  │
│  │  │  EC2: K3s Master (t3.medium)                        │   │  │
│  │  │  ├── K3s Server (control plane)                     │   │  │
│  │  │  ├── Jenkins (Docker container, port 8080)          │   │  │
│  │  │  └── Workloads (monitoring, logging, vault)         │   │  │
│  │  │                                                     │   │  │
│  │  └─────────────────────────────────────────────────────┘   │  │
│  │                                                            │  │
│  │  ┌─── Public Subnet 2 (10.0.2.0/24) ──────────────────┐   │  │
│  │  │                                                     │   │  │
│  │  │  EC2: K3s Worker (t3.medium)                        │   │  │
│  │  │  └── Workloads (app pods, database, cache)          │   │  │
│  │  │                                                     │   │  │
│  │  └─────────────────────────────────────────────────────┘   │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ECR: safecity-api, safecity-dashboard                           │
│  S3:  safecity-backups-{account-id}                              │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Kubernetes Cluster Layout

| Namespace    | Components                                      | Purpose                          |
|-------------|------------------------------------------------|----------------------------------|
| `safecity`   | API (2 pods), Dashboard (2 pods), PostgreSQL, Redis | Application workloads           |
| `monitoring` | Prometheus, Grafana, Alertmanager              | Metrics & alerting               |
| `logging`    | Loki, Promtail (DaemonSet)                     | Centralized log aggregation      |
| `vault`      | HashiCorp Vault (dev mode)                     | Secrets management               |

## Application Stack

### SafeCity API (FastAPI)
- **Runtime**: Python 3.12, FastAPI, SQLAlchemy
- **Database**: PostgreSQL 16
- **Cache**: Redis 7
- **Endpoints**: Incident CRUD, analytics, threat assessment, sensor data
- **Metrics**: Prometheus metrics at `/metrics` via `prometheus-fastapi-instrumentator`
- **Probes**: `/health` (liveness), `/ready` (readiness)

### SafeCity Dashboard (Flask)
- **Runtime**: Python 3.12, Flask, Gunicorn
- **Design**: Minimalist, server-rendered with Jinja2 templates
- **Pages**: Operations overview, incidents list, analytics & threat assessment

## CI/CD Pipeline (Jenkins)

```
Checkout → Lint & Test → Docker Build → Push to ECR → Deploy to K3s → Smoke Test
                                                                        ↓
                                                              (on failure: auto-rollback)
```

## Monitoring & Observability

| Tool         | Purpose                | Access              |
|-------------|------------------------|----------------------|
| Prometheus   | Metrics collection     | `:30090`            |
| Grafana      | Dashboards & viz       | `:30030` (admin/safecity) |
| Alertmanager | Alert routing          | Internal (`:9093`)  |
| Loki         | Log aggregation        | Internal (`:3100`)  |
| Promtail     | Log collection         | DaemonSet           |

## Security

- **Network Policies**: Default-deny ingress in `safecity` namespace
- **Vault**: Centralized secrets for DB credentials, API keys, JWT secrets
- **Non-root containers**: Both API and Dashboard run as non-root users
- **ECR image scanning**: Enabled on push
- **S3 encryption**: AES-256 server-side encryption
- **IAM least privilege**: Instance profile with scoped ECR, S3, SSM access only

## Disaster Recovery

- **RTO**: < 15 minutes (re-deploy from backup)
- **RPO**: < 1 hour (scheduled backups)
- **Backup targets**: K3s etcd snapshots, PostgreSQL dumps, K8s resource manifests
- **Storage**: S3 with versioning, 30-day lifecycle policy
- **Scripts**: `backup.sh`, `restore.sh`, `simulate-outage.sh`
