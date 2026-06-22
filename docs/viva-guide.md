# SafeCity DevOps — VIVA Reference Guide

## 1. Docker

**What it is:** Containerization platform that packages applications with their dependencies into lightweight, portable containers.

**Real-world use:** Standardized packaging and deployment — "works on my machine" problem solver. Used everywhere from dev laptops to production servers.

**In-depth explanation:**
Docker uses OS-level virtualization to run isolated user-space environments called containers. Unlike VMs (which virtualize hardware + run a full OS), containers share the host OS kernel and only include the app + its dependencies (libraries, binaries, config files). This makes them far lighter — milliseconds to start vs minutes for VMs.

**Key components:**
- **Dockerfile** — Blueprint with instructions (FROM, COPY, RUN, EXPOSE, CMD) to build an image
- **Image** — Immutable snapshot (read-only template). Built from a Dockerfile, stored in a registry
- **Container** — Running instance of an image. Has its own filesystem, network, process tree
- **Docker Daemon (dockerd)** — Background service that manages images, containers, networks, volumes
- **Docker Client (docker CLI)** — Frontend that talks to the daemon via REST API
- **Docker Registry** — Stores/distributes images. Docker Hub (public) or ECR (private)
- **Docker Compose** — Define/run multi-container apps with a single YAML file (used for local dev)
- **Bind Mounts / Volumes** — Persistent storage; data survives container restarts

**In our project:** Each service (API, Dashboard) has a Dockerfile. Jenkins builds images and pushes to ECR. Kubernetes pulls those images to run pods.

---

## 2. Kubernetes (K8s) / Amazon EKS

**What it is:** Container orchestration platform — automates deployment, scaling, and management of containerized applications.

**Real-world use:** Running microservices in production. Handles rolling updates, auto-scaling, self-healing, load balancing, secrets management across a cluster of machines.

**In-depth explanation:**
Kubernetes manages a cluster of nodes (EC2 instances). You declare your desired state (e.g., "2 replicas of safecity-api, image v10, port 8000") in YAML manifests, and K8s constantly works to match the actual state to the desired state. If a pod crashes, it replaces it. If traffic spikes, it can auto-scale. If you roll out a bad update, it can roll back.

**Key components:**
- **Cluster** — Set of worker nodes (machines) + control plane
- **Control Plane** — Brain of the cluster:
  - **kube-apiserver** — Frontend; all communication goes through it (REST)
  - **etcd** — Distributed key-value store; stores all cluster state
  - **kube-scheduler** — Assigns pods to nodes based on resources/constraints
  - **kube-controller-manager** — Runs controllers (Deployment, ReplicaSet, Node, etc.)
- **Node (worker)** — EC2 instance running:
  - **kubelet** — Agent that ensures containers are running in pods
  - **kube-proxy** — Network proxy; handles service routing/load balancing
- **Pod** — Smallest deployable unit; 1+ containers sharing network/storage
- **Deployment** — Declarative update for Pods + ReplicaSets (rolling updates, rollbacks)
- **Service** — Stable network endpoint (ClusterIP, NodePort, LoadBalancer) that load-balances across pods
- **Namespace** — Virtual cluster within a cluster (isolates resources). We use `safecity`
- **ConfigMap / Secret** — Inject configuration/sensitive data into pods
- **Ingress** — HTTP/HTTPS routing rules (not implemented yet in our project)

**In our project:** We have Deployments for `safecity-api`, `safecity-dashboard`, `redis`, and a StatefulSet for `postgres`. All in the `safecity` namespace. Kubernetes handles pod health, restarts, and network connectivity.

---

## 3. Jenkins

**What it is:** CI/CD (Continuous Integration / Continuous Deployment) automation server.

**Real-world use:** Automates the build-test-deploy pipeline. Every time developers push code, Jenkins runs tests, builds artifacts, and deploys to production — automatically.

**In-depth explanation:**
Jenkins follows the "Pipeline as Code" paradigm. The entire workflow (checkout → test → build → push → deploy) is defined in a `Jenkinsfile` checked into the repository. Jenkins monitors SCM (GitHub) for changes, triggers pipelines, and reports results.

**Key components:**
- **Master Node (Jenkins server)** — Manages job scheduling, serves UI/API, stores build history. Runs inside a Docker container on our EC2 instance
- **Agent (Executor)** — Machine that runs actual build steps. We run `agent any` (uses the master node itself)
- **Job / Pipeline** — A defined automation workflow. Ours is a "Pipeline" job (multi-stage)
- **Stages** — Logical phases: Checkout → Test → Login to ECR → Build & Push → Deploy to K8s
- **Steps** — Individual actions within a stage (`sh`, `checkout scm`, etc.)
- **SCM Integration** — Fetches code from GitHub on every build
- **Build Artifacts** — Not used here; we push Docker images instead
- **Jenkinsfile** — Groovy-based DSL defining the pipeline:
  - `pipeline {}` — Root block
  - `environment {}` — Environment variables (AWS_REGION, ECR URI, image names)
  - `stages {}` — Sequential stages
  - `post {}` — Post-build actions (success/failure notifications)
- **Plugins** — Git Pipeline plugin, AWS CLI (via `sh`), Docker Pipeline, etc.

**In our project:** Jenkins automates: 1) Run tests in Docker containers, 2) Build production images, 3) Push to ECR, 4) Deploy to EKS via `kubectl set image`. Each build is triggered by pushes to GitHub master branch or manually.

---

## 4. Terraform

**What it is:** Infrastructure as Code (IaC) tool — define cloud resources in HCL (HashiCorp Configuration Language).

**Real-world use:** Provision and manage cloud infrastructure (VPCs, EC2, EKS, RDS, IAM, etc.) declaratively. Changes are reviewed, version-controlled, and repeatable.

**In-depth explanation:**
Instead of clicking around the AWS Console or writing shell scripts, you describe your infrastructure in `.tf` files. Terraform computes a "plan" (what will change), then "applies" it. It maintains a state file that maps real-world resources to your config, so it knows what to create/update/delete.

**Key components:**
- **Providers** — Plugins that interact with cloud APIs (AWS, GCP, Azure). We use `hashicorp/aws`
- **Resources** — Infrastructure objects (`aws_vpc`, `aws_eks_cluster`, `aws_iam_role`, etc.)
- **Data Sources** — Read existing resources (`aws_eks_cluster_auth`, `aws_availability_zones`)
- **Variables** — Input parameters (`variable "cluster_name" {}`)
- **Outputs** — Return values after apply (`output "cluster_endpoint" {}`)
- **State File (`terraform.tfstate`)** — JSON mapping of what's been created. Critical — must be backed up
- **Modules** — Reusable groups of resources. We use the `terraform-aws-modules/eks/aws` module (the "blue-green" or "irsa" approach)
- **HCL Syntax** — Declarative language (not procedural). Terraform figures out the order of operations
- **Plan / Apply Workflow:**
  1. `terraform init` — Download providers, initialize backend
  2. `terraform plan` — Show what will be created/changed/destroyed
  3. `terraform apply` — Execute the plan
  4. `terraform destroy` — Tear everything down

**In our project:** Terraform provisions the entire EKS cluster — VPC, subnets, EKS control plane, managed node group, IAM roles, security groups. The bootstrap script runs `terraform apply` automatically. The kubeconfig is extracted via `aws eks update-kubeconfig`.

---

## 5. Prometheus

**What it is:** Open-source monitoring and alerting toolkit — scrapes and stores time-series metrics.

**Real-world use:** Collect metrics from applications and infrastructure (CPU, memory, request latency, error rates, custom business metrics). Often paired with Grafana for visualization.

**In-depth explanation:**
Prometheus uses a "pull" model — it periodically scrapes HTTP endpoints (`/metrics`) that expose metrics in plaintext format. Each metric has a name, value, timestamp, and optional labels (key-value pairs used for filtering/aggregation). PromQL (Prometheus Query Language) is used to query and aggregate metrics.

**Key components:**
- **Prometheus Server** — Core component:
  - **TSDB (Time Series Database)** — Stores metrics efficiently with compression
  - **Scraper** — Pulls metrics from targets at configured intervals
  - **Rule Engine** — Evaluates recording rules and alerting rules
  - **HTTP API** — Serves metrics and supports queries (used by Grafana)
- **Exporters** — Bridge tools that expose third-party metrics:
  - **kube-state-metrics** — K8s object metrics (deployments, pods, etc.)
  - **node-exporter** — Host-level metrics (CPU, memory, disk)
- **Alertmanager** — Deduplicates/sends alerts (not configured in our project yet)
- **Service Monitors** — K8s CRDs that tell Prometheus which pods to scrape and how
- **PromQL** — Query language:
  - `rate(http_requests_total[5m])` — Per-second request rate over 5 minutes
  - `histogram_quantile(0.95, ...)` — 95th percentile latency
- **Targets** — Endpoints being scraped (identified by `__meta_kubernetes_pod_label_app`)
- **Relabel Configs** — Transform/select which targets to scrape and label them

**In our project:** Prometheus is deployed via Helm with custom relabel configs. It scrapes:
- `safecity-api` pods (port 8000, path `/metrics`) — Flask app metrics via prometheus_flask_exporter
- `safecity-dashboard` pods (port 5000, path `/metrics`) — Dashboard metrics
- kube-state-metrics and node-exporter for cluster health

---

## 6. Grafana

**What it is:** Open-source analytics and visualization platform — creates dashboards from time-series data.

**Real-world use:** Visualize metrics from Prometheus, Elasticsearch, CloudWatch, etc. Create operational dashboards for SRE/DevOps teams to monitor system health.

**In-depth explanation:**
Grafana connects to data sources (like Prometheus), queries them, and renders interactive dashboards with panels (graphs, tables, gauges, stat displays). Users can set up alerts, annotations, and ad-hoc filtering.

**Key components:**
- **Data Sources** — Backend databases it queries. We use Prometheus as our data source
- **Dashboards** — Collections of panels arranged in rows/columns. JSON-based; can be imported/exported
- **Panels** — Individual visualizations:
  - **Time Series** — Line/area charts over time (e.g., request latency, error rates)
  - **Stat** — Single number display (e.g., current error rate)
  - **Table** — Tabular data
  - **Bar Gauge / Pie Chart** — Distribution views
- **Queries** — PromQL expressions that fetch data for each panel. Example: `rate(http_request_duration_seconds_count[5m])`
- **Variables** — Interactive filters (e.g., namespace selector, pod selector)
- **Alerting** — Define threshold-based alerts from panel queries (not configured)
- **Provisioning** — Dashboards and data sources configured as YAML files (checked into repo)
- **UID** — Unique identifier for dashboards/datasources. Must match between provisioning files

**In our project:** Grafana is deployed as a K8s Deployment with a ConfigMap containing:
- `datasources.yaml` — Configures Prometheus as the data source with `uid: prometheus`
- `dashboards.yaml` — Lists dashboard JSON files to auto-import
- Dashboard JSON — Pre-built dashboard showing: request rate, error rate (4xx/5xx), p95 latency, API endpoints table, uptime, etc.

---

## 7. HashiCorp Vault

**What it is:** Secrets management tool — securely stores, controls access to, and audits secrets (DB passwords, API keys, tokens).

**Real-world use:** Instead of hardcoding secrets in environment variables or config files, apps fetch them dynamically at runtime. Centralized audit trail for who accessed what secret.

**In-depth explanation:**
Vault provides a unified API to access secrets. It supports multiple "secret engines" and "auth methods." Secrets can be static (stored in Vault) or dynamic (generated on-demand with TTL). All access is logged.

**Key components:**
- **Vault Server** — Core service providing the API. Runs in dev mode (`-dev`) or production with HA
- **Seal / Unseal** — Vault starts sealed (encrypted). Must be unsealed with keys to access contents
- **Secret Engines** — Backends that store/generate secrets:
  - **KV (Key-Value) v2** — Simple static secrets (like a dictionary). We use this for DB credentials
- **Auth Methods** — How clients authenticate:
  - **Token** — Simple bearer token (we use root token for simplicity in development)
  - Kubernetes — Pod-bound tokens (production approach)
- **Policies** — ACL rules mapping paths to capabilities (read, create, update, delete, list)
- **Vault Agent Sidecar** — Injects secrets into pods as files/env vars (not implemented; our app reads via API)
- **Audit Device** — Logs all requests and responses

**In our project:** Vault runs as a K8s Deployment seeded with DB credentials. The API and Dashboard fetch secrets at startup via HTTP requests to the Vault API. A seeder Job ensures secrets are written before apps start.

---

## 8. Amazon ECR (Elastic Container Registry)

**What it is:** Fully managed Docker container registry on AWS.

**Real-world use:** Store, manage, and deploy Docker images privately. Integrated with EKS for image pulls.

**In-depth explanation:**
ECR stores Docker images in repositories. Each image is identified by a tag (e.g., `safecity-api:10`). Images are pushed via `docker push` (after authenticating with ECR) and pulled by Kubernetes nodes during pod creation.

**Components:**
- **Repository** — Collection of images (e.g., `safecity-api`)
- **Tag** — Version identifier (`latest`, `10`, `v1.0`)
- **Lifecycle Policy** — Auto-delete old images to save storage costs
- **IAM Policies** — Control who can push/pull. Nodes have `AmazonEC2ContainerRegistryReadOnly` role

**In our project:** Jenkins authenticates with ECR via `aws ecr get-login-password`, builds images tagged with `latest` and `BUILD_NUMBER`, pushes both, and Kubernetes deployments reference the tagged image.

---

## 9. GitHub

**What it is:** Git repository hosting with collaboration features (PRs, Actions, webhooks).

**Real-world use:** Version control — tracks code changes, enables collaboration, triggers CI/CD pipelines.

**Components:**
- **Repository** — Project code + history
- **Branching** — `master` (main) branch; feature branches for development
- **Webhooks** — HTTP callbacks that notify Jenkins of pushes (triggers builds)
- **SCM** — Source Code Management; Jenkins checks out code from here

**In our project:** GitHub hosts the SafeCity repo. Jenkins watches the `master` branch. On each push, Jenkins automatically checks out the latest code and runs the pipeline.

---

## 10. PostgreSQL

**What it is:** Open-source relational database (RDBMS).

**Real-world use:** Primary data store for applications needing ACID transactions, complex queries, and relational data.

**Key components:**
- **StatefulSet** — K8s resource for stateful apps (stable network identity, persistent storage)
- **PersistentVolume (PV) / PersistentVolumeClaim (PVC)** — Durable storage that survives pod restarts
- **Service** — Stable DNS name for other pods to reach the database
- **Init Container** — Runs before the main container to set permissions, create DBs, run migrations

**In our project:** PostgreSQL runs as a StatefulSet with persistent storage (gp2 EBS volume via gp2 StorageClass). It stores incident reports, analytics data, alerts.

---

## 11. Redis

**What it is:** In-memory key-value store (often used as cache/message broker).

**Real-world use:** Caching database queries, session storage, rate limiting, pub/sub messaging, real-time leaderboards.

**Key components:**
- **Deployment** — Managed as a stateless app (no persistent storage needed; cache is ephemeral)
- **Service** — ClusterIP for internal pod communication

**In our project:** Redis caches API responses (analytics queries, incident lists) to reduce database load and improve response times. Uses LRU eviction when memory fills up.

---

## 12. AWS (Amazon Web Services)

**What it is:** Cloud computing platform providing on-demand compute, storage, networking, and more.

**Services used:**
- **EC2 (Elastic Compute Cloud)** — Virtual servers. Our Jenkins server runs on a `t3.small` EC2 instance. EKS worker nodes are also EC2 instances (auto-scaling group)
- **EKS (Elastic Kubernetes Service)** — Managed Kubernetes control plane. We don't manage the master — AWS handles etcd, API server, scheduler HA
- **EBS (Elastic Block Store)** — Persistent block storage. Used by EKS for PVCs (PostgreSQL data)
- **ELB (Elastic Load Balancer)** — Distributes traffic. EKS creates NLBs for LoadBalancer-type Services
- **IAM (Identity & Access Management)** — Users, roles, policies. Jenkins instance has an IAM role for ECR push + EKS access. Node group has roles for ECR pull + EKS cluster join
- **VPC (Virtual Private Cloud)** — Isolated network. EKS cluster lives in a custom VPC with public/private subnets

---

## Architecture Diagram (Text)

```
GitHub ──webhook──> Jenkins (EC2)
                       │
              ┌────────┼────────────┐
              ▼        ▼            ▼
          Tests    Build Images   Deploy
              │        │            │
              ▼        ▼            ▼
          Docker    Push to      kubectl set image
          (local)   ECR (AWS)    ──────────────► EKS Cluster
                                              ┌─────────────┐
                                              │  safecity   │
                                              │  namespace  │
                                              │             │
                                              │  API x2     │
                                              │  Dashboard  │
                                              │  x2         │
                                              │  Postgres   │
                                              │  Redis      │
                                              │  Vault      │
                                              │  Prometheus │
                                              │  Grafana    │
                                              └─────────────┘
```

## Testing Overview

- **API Tests:** 16 pytest tests – health check, CRUD operations on incidents, analytics queries
- **Dashboard Tests:** 7 pytest tests – route rendering, form submission, health endpoints
- Tests run inside ephemeral Docker containers (isolated from the running cluster)
- No test database or mocking – tests use SQLite in-memory
