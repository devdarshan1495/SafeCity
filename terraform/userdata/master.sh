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
echo "[1/8] Updating system packages …"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip jq \
    apt-transport-https ca-certificates \
    software-properties-common gnupg \
    postgresql-client awscli

# ── Install Docker ──────────────────────────────────────────────
echo "[2/8] Installing Docker …"
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# ── Install K3s Server ──────────────────────────────────────────
echo "[3/8] Installing K3s server …"
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
echo "[4/8] Storing K3s join token in SSM …"
K3S_JOIN_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
aws ssm put-parameter \
    --name "/$SC_PROJECT/k3s-token" \
    --value "$K3S_JOIN_TOKEN" \
    --type SecureString \
    --overwrite \
    --region "$SC_REGION"

# ── Setup kubeconfig for ubuntu user ────────────────────────────
echo "[5/8] Configuring kubectl for ubuntu user …"
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
echo 'export KUBECONFIG=/home/ubuntu/.kube/config' >> /home/ubuntu/.bashrc

# ── Install Helm ────────────────────────────────────────────────
echo "[6/8] Installing Helm …"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── Setup Jenkins (Docker container) ────────────────────────────
echo "[7/8] Starting Jenkins …"
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

# ── Auto-Configure Jenkins (background) ─────────────────────────
cat > /home/ubuntu/jenkins-setup.sh << JENKINSSETUP
#!/bin/bash
set -e

JENKINS_URL="http://localhost:8080"
echo "Waiting for Jenkins to be ready …"
for i in \$(seq 1 36); do
    HTTP_CODE=\$(curl -s -o /dev/null -w '%%{http_code}' "\$JENKINS_URL/login" 2>/dev/null || echo "000")
    if [ "\$HTTP_CODE" != "000" ] && [ "\$HTTP_CODE" != "503" ]; then
        echo "Jenkins is ready (HTTP \$HTTP_CODE)."
        break
    fi
    sleep 10
done

JENKINS_PASS=\$(docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword)
echo "Jenkins admin password obtained."

# Download CLI
curl -s "\$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar

# Install plugins
echo "Installing Jenkins plugins …"
java -jar /tmp/jenkins-cli.jar -auth "admin:\$JENKINS_PASS" install-plugin \
    git pipeline-model-definition docker-workflow credentials-binding || true

# Wait for plugin installs
echo "Waiting for plugins to finalize …"
sleep 30

# Create the pipeline job
echo "Creating pipeline job …"
cat > /tmp/safecity-job.xml << 'XML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="pipeline-model-definition">
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/devdarshan1495/SafeCity.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/master</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XML

if java -jar /tmp/jenkins-cli.jar -auth "admin:\$JENKINS_PASS" create-job safecity-pipeline < /tmp/safecity-job.xml 2>/dev/null; then
    echo "Pipeline job 'safecity-pipeline' created."
else
    java -jar /tmp/jenkins-cli.jar -auth "admin:\$JENKINS_PASS" update-job safecity-pipeline < /tmp/safecity-job.xml 2>/dev/null || true
    echo "Pipeline job updated."
fi

# Set a known admin password so the UI is always accessible
echo "Setting Jenkins admin password to 'safecity' …"
java -jar /tmp/jenkins-cli.jar -auth "admin:\$JENKINS_PASS" groovy = \
    'hudson.model.User.get("admin").setPassword("safecity")' 2>/dev/null || true
echo "Jenkins setup complete — login: admin / safecity"
JENKINSSETUP

chmod +x /home/ubuntu/jenkins-setup.sh
chown ubuntu:ubuntu /home/ubuntu/jenkins-setup.sh
nohup /home/ubuntu/jenkins-setup.sh > /var/log/jenkins-setup.log 2>&1 &
echo "Jenkins setup script launched in background."

# ── Setup Backup & DR Scripts ──────────────────────────────────
SC_ACCOUNT="${account_id}"
BACKUP_BUCKET="safecity-backups-$SC_ACCOUNT"

# backup.sh — uses unquoted heredoc to inject BACKUP_BUCKET, escapes internal $ signs
cat > /home/ubuntu/backup.sh << BACKUPEOF
#!/bin/bash
set -euo pipefail

S3_BUCKET="$BACKUP_BUCKET"
BACKUP_DIR="/tmp/backups/safecity-\$(date +%Y%m%d-%H%M%S)"
NAMESPACES="safecity monitoring logging vault"

mkdir -p "\$BACKUP_DIR"/{etcd,postgres,kubernetes}

echo "[backup] Exporting Kubernetes resources ..."
for ns in \$NAMESPACES; do
    kubectl get all -n "\$ns" -o yaml >> "\$BACKUP_DIR/kubernetes/resources-\$ns.yaml" 2>/dev/null || true
done
kubectl get pvc --all-namespaces -o yaml >> "\$BACKUP_DIR/kubernetes/pvc.yaml" 2>/dev/null || true
kubectl get configmap --all-namespaces -o yaml >> "\$BACKUP_DIR/kubernetes/configmaps.yaml" 2>/dev/null || true
kubectl get secret --all-namespaces -o yaml >> "\$BACKUP_DIR/kubernetes/secrets.yaml" 2>/dev/null || true

echo "[backup] Dumping PostgreSQL ..."
kubectl exec -n safecity postgres-0 -- sh -c 'PGPASSWORD=safecity_prod_pass pg_dump -U safecity safecity' \
    > "\$BACKUP_DIR/postgres/dump.sql" 2>/dev/null || echo "[backup] WARNING: Postgres dump failed"

echo "[backup] Snapshotting K3s etcd ..."
k3s etcd-snapshot save --snapshot-dir="\$BACKUP_DIR/etcd" 2>/dev/null || echo "[backup] WARNING: etcd snapshot failed"

echo "[backup] Uploading to S3 ..."
aws s3 sync "\$BACKUP_DIR" "s3://\$S3_BUCKET/safecity-backups/\$(basename \$BACKUP_DIR)/" --quiet

echo "[backup] Pruning backups older than 7 days ..."
aws s3 ls "s3://\$S3_BUCKET/safecity-backups/" | while read -r line; do
    FOLDER=\$(echo "\$line" | awk '{print \$NF}')
    TIMESTAMP=\$(echo "\$line" | awk '{print \$1" "\$2}')
    if [ "\$(date -d "\$TIMESTAMP" +%s 2>/dev/null)" -lt "\$(date -d '7 days ago' +%s)" ]; then
        aws s3 rm "s3://\$S3_BUCKET/safecity-backups/\$FOLDER" --recursive --quiet
        echo "[backup] Pruned: \$FOLDER"
    fi
done 2>/dev/null || true

echo "[backup] Complete."
BACKUPEOF

# dr-restore.sh
cat > /home/ubuntu/dr-restore.sh << DRRESTOREEOF
#!/bin/bash
set -euo pipefail

S3_BUCKET="$BACKUP_BUCKET"

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity DR Restore — \$(date)"
echo "═══════════════════════════════════════════════════════"

LATEST=\$(aws s3 ls "s3://\$S3_BUCKET/safecity-backups/" | sort | tail -1 | awk '{print \$NF}')
if [ -z "\$LATEST" ]; then
    echo "No backups found in s3://\$S3_BUCKET/safecity-backups/"
    exit 1
fi
echo "Restoring from: \$LATEST"

RESTORE_DIR="/tmp/dr-restore"
mkdir -p "\$RESTORE_DIR"
aws s3 sync "s3://\$S3_BUCKET/safecity-backups/\$LATEST" "\$RESTORE_DIR" --quiet

if [ -f "\$RESTORE_DIR/postgres/dump.sql" ]; then
    echo "[DR] Restoring PostgreSQL ..."
    until kubectl get pod -n safecity postgres-0 -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running; do
        sleep 5
    done
    kubectl exec -n safecity postgres-0 -- sh -c 'PGPASSWORD=safecity_prod_pass psql -U safecity -d postgres -c "DROP DATABASE IF EXISTS safecity;" 2>/dev/null; PGPASSWORD=safecity_prod_pass psql -U safecity -d postgres -c "CREATE DATABASE safecity;" 2>/dev/null'
    kubectl exec -n safecity postgres-0 -i -- sh -c 'PGPASSWORD=safecity_prod_pass psql -U safecity safecity' \
        < "\$RESTORE_DIR/postgres/dump.sql"
    echo "[DR] PostgreSQL restored."
else
    echo "[DR] No PostgreSQL backup found."
fi

if [ -d "\$RESTORE_DIR/kubernetes" ]; then
    echo "[DR] Re-applying Kubernetes resources ..."
    for f in "\$RESTORE_DIR/kubernetes/"*.yaml; do
        [ -f "\$f" ] && kubectl apply -f "\$f" 2>/dev/null || true
    done
    echo "[DR] Kubernetes resources applied."
fi

echo "DR Restore COMPLETE."
DRRESTOREEOF

chmod +x /home/ubuntu/backup.sh /home/ubuntu/dr-restore.sh
chown ubuntu:ubuntu /home/ubuntu/backup.sh /home/ubuntu/dr-restore.sh

# Schedule daily backup via cron
echo "0 2 * * * root /home/ubuntu/backup.sh > /var/log/safecity-backup.log 2>&1" > /etc/cron.d/safecity-backup
chmod 644 /etc/cron.d/safecity-backup

echo "Backup and DR scripts installed (daily 2 AM cron)."

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
echo "  Jenkins:   http://$SC_PUBLIC_IP:8080 (admin / safecity)"
echo "  Jenkins pipeline: safecity-pipeline (auto-created)"
echo "  Backups:   s3://$BACKUP_BUCKET/safecity-backups/ (daily 2 AM cron)"
echo "  DR restore: sudo /home/ubuntu/dr-restore.sh"
echo "═══════════════════════════════════════════════════════"
