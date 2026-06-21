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
    postgresql-client

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

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity Master Bootstrap COMPLETE — $(date)"
echo "  K3s server: running"
echo "  Jenkins: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "  Jenkins initial password: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
echo "═══════════════════════════════════════════════════════"
