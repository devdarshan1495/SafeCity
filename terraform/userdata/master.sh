#!/bin/bash
# ── SafeCity — K3s Master Bootstrap ──────────────────────────────
# Runs as EC2 userdata on the master node.
# Installs: K3s server, Docker, kubectl, Helm, AWS CLI tools
# Stores K3s join token in SSM Parameter Store for workers.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail
exec > >(tee /var/log/safecity-bootstrap.log) 2>&1

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity K3s Master Bootstrap — $(date)"
echo "═══════════════════════════════════════════════════════"

export DEBIAN_FRONTEND=noninteractive
SC_REGION="${aws_region}"
SC_PROJECT="${project_name}"
SC_ECR="${ecr_registry}"
SC_ACCOUNT="${account_id}"
BACKUP_BUCKET="safecity-backups-$SC_ACCOUNT"

# ── System Updates ──────────────────────────────────────────────
echo "[1/8] Updating system packages …"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip jq \
    apt-transport-https ca-certificates \
    software-properties-common gnupg \
    postgresql-client awscli

# ── Swap & Memory Tuning ─────────────────────────────────────────
echo "[2/9] Creating 2GB swap & tuning memory …"
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab
echo "vm.swappiness=10" >> /etc/sysctl.conf
echo "vm.overcommit_memory=1" >> /etc/sysctl.conf
sysctl -p
free -h

# ── Install Docker ──────────────────────────────────────────────
echo "[3/9] Installing Docker …"
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Open Docker socket permissions so Jenkins container can access it
chmod 666 /var/run/docker.sock
# Persist across reboots: ExecStartPost on docker.service
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/socket-perms.conf << 'EOF'
[Service]
ExecStartPost=/bin/chmod 666 /var/run/docker.sock
EOF
systemctl daemon-reload

# ── Install K3s Server ──────────────────────────────────────────
echo "[4/9] Installing K3s server …"
curl -sfL https://get.k3s.io | sh -s - server \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --node-name "$SC_PROJECT-master"

# Wait for K3s to be ready
echo "Waiting for K3s to be ready …"
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
    sleep 5
done
echo "K3s server is ready."

# ── Store K3s Token in SSM ──────────────────────────────────────
echo "[5/9] Storing K3s join token in SSM …"
K3S_JOIN_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
aws ssm put-parameter \
    --name "/$SC_PROJECT/k3s-token" \
    --value "$K3S_JOIN_TOKEN" \
    --type SecureString \
    --overwrite \
    --region "$SC_REGION"

# ── Setup kubeconfig for ubuntu user ────────────────────────────
echo "[6/9] Configuring kubectl for ubuntu user …"
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
echo 'export KUBECONFIG=/home/ubuntu/.kube/config' >> /home/ubuntu/.bashrc

# ── Install Helm ────────────────────────────────────────────────
echo "[7/9] Installing Helm …"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── Setup Jenkins (Docker container) ────────────────────────────
echo "[8/9] Starting Jenkins …"
docker volume create jenkins_home

# Fix kubeconfig: K3s defaults to 127.0.0.1, but Jenkins needs the internal IP
SC_INTERNAL_IP=$(hostname -I | awk '{print $1}')
sed "s|server: https://127.0.0.1:6443|server: https://${SC_INTERNAL_IP}:6443|" \
    /etc/rancher/k3s/k3s.yaml > /home/ubuntu/.kube/jenkins-config

docker run -d \
    --name jenkins \
    --restart unless-stopped \
    --group-add 998 \
    -p 8080:8080 \
    -p 50000:50000 \
    -v jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /usr/bin/docker:/usr/bin/docker \
    -v /home/ubuntu/.kube/jenkins-config:/var/jenkins_home/.kube/config:ro \
    -v /home/ubuntu/.aws:/var/jenkins_home/.aws:ro \
    -e JAVA_OPTS="-Xmx384m" \
    jenkins/jenkins:lts

# Install tools inside Jenkins container
docker exec -u root jenkins bash -c "
  curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl &&
  chmod +x /usr/local/bin/kubectl &&
  apt-get update -qq && apt-get install -y -qq awscli
"

# ECR login helper script
cat > /home/ubuntu/ecr-login.sh << ECREOF
#!/bin/bash
aws ecr get-login-password --region $SC_REGION | \\
    docker login --username AWS --password-stdin $SC_ECR
echo "ECR login successful."
ECREOF
chmod +x /home/ubuntu/ecr-login.sh
chown ubuntu:ubuntu /home/ubuntu/ecr-login.sh

# ── Create K8s Namespaces ───────────────────────────────────────
echo "Creating Kubernetes namespaces …"
kubectl create namespace safecity --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

# ── Deploy Application ────────────────────────────────────────
echo "[9/9] Deploying SafeCity application …"

SC_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
SC_REPO="https://github.com/devdarshan1495/SafeCity.git"
SC_DIR="/home/ubuntu/safecity"

# Clone the repo
if [ ! -d "$SC_DIR" ]; then
    git clone "$SC_REPO" "$SC_DIR"
fi
cd "$SC_DIR"

# Copy scripts from repo and set up scheduled tasks
cp scripts/backup.sh scripts/dr-restore.sh /home/ubuntu/
chmod +x /home/ubuntu/backup.sh /home/ubuntu/dr-restore.sh
chown ubuntu:ubuntu /home/ubuntu/backup.sh /home/ubuntu/dr-restore.sh
cat > /etc/cron.d/safecity-backup << CRONEOF
0 2 * * * root /home/ubuntu/backup.sh $BACKUP_BUCKET > /var/log/safecity-backup.log 2>&1
CRONEOF
chmod 644 /etc/cron.d/safecity-backup

cp scripts/jenkins-setup.sh /home/ubuntu/jenkins-setup.sh
chmod +x /home/ubuntu/jenkins-setup.sh
chown ubuntu:ubuntu /home/ubuntu/jenkins-setup.sh
nohup /home/ubuntu/jenkins-setup.sh > /var/log/jenkins-setup.log 2>&1 &

# Login to ECR
aws ecr get-login-password --region "$SC_REGION" | docker login --username AWS --password-stdin "$SC_ECR"

# Build and push images
docker build -t "$SC_ECR/safecity-api:latest" app/api/
docker build -t "$SC_ECR/safecity-dashboard:latest" app/dashboard/
docker push "$SC_ECR/safecity-api:latest"
docker push "$SC_ECR/safecity-dashboard:latest"

# Update manifests with image URLs
sed -i "s|SAFECITY_API_IMAGE|$SC_ECR/safecity-api:latest|g" kubernetes/app/api-deployment.yaml
sed -i "s|SAFECITY_DASHBOARD_IMAGE|$SC_ECR/safecity-dashboard:latest|g" kubernetes/app/dashboard-deployment.yaml

# Wait for worker to join (up to 3 minutes)
echo "Waiting for worker node to join …"
for i in $(seq 1 36); do
    if kubectl get nodes 2>/dev/null | grep -v master | grep -q Ready; then
        echo "Worker node joined."
        break
    fi
    sleep 5
done

# Create ECR pull secret for K8s
kubectl create secret docker-registry ecr-pull \
    --docker-server="$SC_ECR" \
    --docker-username=AWS \
    --docker-password="$(aws ecr get-login-password --region "$SC_REGION")" \
    --namespace=safecity \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl patch serviceaccount default -n safecity \
    -p '{"imagePullSecrets": [{"name": "ecr-pull"}]}'

# Apply all Kubernetes manifests (recursive for subdirectories)
kubectl apply -f kubernetes/namespaces.yaml
kubectl apply -f kubernetes/app/
kubectl apply -f kubernetes/monitoring/
kubectl apply -f kubernetes/logging/
kubectl apply -f kubernetes/vault/
kubectl apply -f kubernetes/network-policies/
# ── Wait for All Services to Be Healthy ────────────────────────
echo "Waiting for all services to become healthy …"

wait_for_http() {
    local url="$1"
    local name="$2"
    local max="$3"
    for i in $(seq 1 "$max"); do
        code=$(curl -s -o /dev/null -w '%%{http_code}' "$url" 2>/dev/null || echo "000")
        case "$code" in
            200|302|301|403) echo "  [$name] OK (HTTP $code)"; return 0 ;;
        esac
        sleep 10
    done
    echo "  [$name] TIMEOUT after $((max * 10))s (last code: $code)"
    return 1
}

wait_for_pod() {
    local ns="$1"
    local app="$2"
    local max="$3"
    for i in $(seq 1 "$max"); do
        status=$(kubectl get pods -n "$ns" -l app="$app" -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
        if echo "$status" | grep -q "Running"; then
            echo "  [pod/$app] Running"
            return 0
        fi
        sleep 10
    done
    echo "  [pod/$app] TIMEOUT"
    return 1
}

# Pod-level checks (up to 4 min)
wait_for_pod safecity postgres 24
wait_for_pod safecity redis 24
wait_for_pod safecity safecity-api 24
wait_for_pod safecity safecity-dashboard 24
wait_for_pod monitoring prometheus 24
wait_for_pod monitoring grafana 24

# HTTP-level checks (up to 2 more min)
wait_for_http "http://localhost:8000/health" "API" 12
wait_for_http "http://localhost:5000/health" "Dashboard" 12
wait_for_http "http://localhost:30090/-/ready" "Prometheus" 6
wait_for_http "http://localhost:30030/login" "Grafana" 6
wait_for_http "http://localhost:8080/login" "Jenkins" 6

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity Master Bootstrap COMPLETE — $(date)"
echo "  K3s server: running"
echo "  Dashboard: http://$SC_PUBLIC_IP:30080"
echo "  API:       http://$SC_PUBLIC_IP:30000"
echo "  Grafana:   http://$SC_PUBLIC_IP:30030 (admin/safecity)"
echo "  Prometheus: http://$SC_PUBLIC_IP:30090"
echo "  Jenkins:   http://$SC_PUBLIC_IP:8080 (admin / safecity)"
echo "  Jenkins pipeline: safecity-pipeline (auto-created)"
echo "  Backups:   s3://$BACKUP_BUCKET/safecity-backups/ (daily 2 AM cron)"
echo "  DR restore: sudo /home/ubuntu/dr-restore.sh"
echo "═══════════════════════════════════════════════════════"
