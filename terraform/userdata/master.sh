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

# ── System Updates ──────────────────────────────────────────────
echo "[1/7] Updating system packages …"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip jq \
    apt-transport-https ca-certificates \
    software-properties-common gnupg \
    postgresql-client awscli

# ── Install Docker ──────────────────────────────────────────────
echo "[2/7] Installing Docker …"
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# ── Install K3s Server ──────────────────────────────────────────
echo "[3/7] Installing K3s server …"
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
echo "[4/7] Storing K3s join token in SSM …"
K3S_JOIN_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
aws ssm put-parameter \
    --name "/$SC_PROJECT/k3s-token" \
    --value "$K3S_JOIN_TOKEN" \
    --type SecureString \
    --overwrite \
    --region "$SC_REGION"

# ── Setup kubeconfig for ubuntu user ────────────────────────────
echo "[5/7] Configuring kubectl for ubuntu user …"
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
echo 'export KUBECONFIG=/home/ubuntu/.kube/config' >> /home/ubuntu/.bashrc

# ── Install Helm ────────────────────────────────────────────────
echo "[6/7] Installing Helm …"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── Setup Jenkins (Docker container) ────────────────────────────
echo "[7/7] Starting Jenkins …"
docker volume create jenkins_home

docker run -d \
    --name jenkins \
    --restart unless-stopped \
    -p 8080:8080 \
    -p 50000:50000 \
    -v jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /usr/bin/docker:/usr/bin/docker \
    -v /home/ubuntu/.kube:/var/jenkins_home/.kube:ro \
    -e JAVA_OPTS="-Xmx512m" \
    jenkins/jenkins:lts

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
echo "[8/8] Deploying SafeCity application …"

SC_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
SC_REPO="https://github.com/devdarshan1495/SafeCity.git"
SC_DIR="/home/ubuntu/safecity"

# Clone the repo
if [ ! -d "$SC_DIR" ]; then
    git clone "$SC_REPO" "$SC_DIR"
fi
cd "$SC_DIR"

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
sleep 15

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity Master Bootstrap COMPLETE — $(date)"
echo "  K3s server: running"
echo "  Dashboard: http://$SC_PUBLIC_IP:30080"
echo "  API:       http://$SC_PUBLIC_IP:30000"
echo "  Grafana:   http://$SC_PUBLIC_IP:30030 (admin/safecity)"
echo "  Prometheus: http://$SC_PUBLIC_IP:30090"
echo "  Jenkins:   http://$SC_PUBLIC_IP:8080"
echo "  Jenkins initial password: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
echo "═══════════════════════════════════════════════════════"
