# SafeCity — Public Safety Analytics Platform

A complete DevOps project: containerized microservices deployed on a production-grade K3s cluster with CI/CD, monitoring, secrets management, and disaster recovery.

## Architecture

```
GitHub ──webhook──> Jenkins (Docker on EC2)
                         │
                ┌───────┼──────────┐
                ▼       ▼          ▼
             Tests   Build      Deploy
                │       │          │
                ▼       ▼          ▼
            Docker    Push to   kubectl set image
            (local)   ECR       ────► K3s Cluster
                                    ┌──────────────┐
                                    │  safecity     │
                                    │  namespace    │
                                    │               │
                                    │  API x2       │
                                    │  Dashboard x2 │
                                    │  Postgres     │
                                    │  Redis        │
                                    │  Vault        │
                                    │  Prometheus   │
                                    │  Grafana      │
                                    └──────────────┘
```

## Tech Stack

| Service | What It Does | Key Components |
|---------|-------------|----------------|
| **Docker** | Containerizes apps with dependencies | Dockerfile, Images, Containers, ECR |
| **K3s** | Lightweight Kubernetes cluster | Master + Worker nodes, Pods, Deployments, Services |
| **Jenkins** | CI/CD automation server | Pipeline, Stages, Jenkinsfile, GitHub webhook |
| **Terraform** | Infrastructure as Code (AWS) | HCL, Providers, State file, Modules |
| **Prometheus** | Metrics collection & time-series DB | Scraper, TSDB, Exporters, PromQL, ServiceMonitors |
| **Grafana** | Dashboards & visualization | Data Sources, Panels, Dashboards, Alerting |
| **Vault** | Secrets management | KV engine, Auth methods, Policies, API |
| **PostgreSQL** | Primary relational database | StatefulSet, PersistentVolume |
| **Redis** | In-memory cache | Deployment, LRU eviction |
| **AWS** | Cloud infrastructure | EC2, ECR, S3, IAM, VPC, EBS |

## Services Exposed

| Service | URL | Port |
|---------|------|------|
| **SafeCity API** | `http://<master-ip>:30000` | 30000 |
| **SafeCity Dashboard** | `http://<master-ip>:30080` | 30080 |
| **Grafana** | `http://<master-ip>:30030` | 30030 |
| **Prometheus** | `http://<master-ip>:30090` | 30090 |
| **Jenkins** | `http://<master-ip>:8080` | 8080 |

## CI/CD Pipeline

The Jenkins pipeline (`Jenkinsfile`) runs automatically on every push to `master`:

1. **Checkout** — Pulls latest code from GitHub
2. **Test API** — Builds test container, runs 16 pytest tests
3. **Test Dashboard** — Builds test container, runs 7 pytest tests
4. **Login to ECR** — Authenticates Docker with AWS ECR
5. **Build & Push** — Builds production images, pushes to ECR with `latest` + `BUILD_NUMBER` tags
6. **Deploy to K8s** — Runs `kubectl set image` to update deployments, waits for rollout

## Monitoring

- **Prometheus** scrapes `/metrics` endpoints from API (Flask exporter) and Dashboard every 15s
- **Grafana** dashboards show: request rate, error rate (4xx/5xx), p95 latency, API endpoints table, uptime
- Services are pre-configured via provisioning YAML files (checked into repo)

## Secrets Management

- **Vault** stores DB credentials securely (KV v2 engine)
- API and Dashboard fetch secrets at startup via Vault HTTP API
- A seeder Job ensures secrets are written before apps start

## Backup & DR

- Automated backup script (`scripts/backup.sh`) backs up etcd, PostgreSQL, and K8s resources to S3
- Disaster recovery script (`scripts/restore.sh`) restores from S3 backup
- S3 bucket versioning + 30-day lifecycle policy
- CronJob runs backups daily at midnight

## Getting Started

### Prerequisites

- AWS account with appropriate permissions
- Terraform >= 1.5
- SSH key pair (`DevAnalytics.pem`)

### Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve

# Bootstrap the cluster
./scripts/bootstrap.sh
```

The bootstrap script:
1. Waits for the master and worker nodes to be ready
2. Installs K3s on both nodes
3. Deploys all K8s manifests (`kubernetes/`)
4. Starts Jenkins via Docker on the master node
5. Pushes Docker images for API and Dashboard
6. Initializes Vault with DB credentials

### Access

After bootstrap completes, outputs show URLs for all services on the master node's public IP.

### Project Structure

```
SafeCity/
├── app/
│   ├── api/          # FastAPI backend — incident CRUD, analytics, Prometheus metrics
│   └── dashboard/    # Flask dashboard — HTML UI, Grafana-style visualization
├── docs/
│   └── viva-guide.md # Comprehensive service explanations for viva
├── jenkins/          # Jenkins configuration
├── kubernetes/       # K8s manifests (Deployments, Services, ConfigMaps)
├── scripts/          # Bootstrap, backup, restore, helper scripts
├── terraform/        # IaC — VPC, EC2, ECR, S3, IAM, Security Groups
├── Jenkinsfile       # CI/CD pipeline definition
└── docker-compose.yml
```

## Destroy

```bash
cd terraform
terraform destroy -auto-approve
```

This removes all AWS resources: EC2 instances, ECR repos, S3 bucket, IAM roles, VPC.
