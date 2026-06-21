#!/bin/bash
# ── SafeCity — K3s Worker Bootstrap ──────────────────────────────
# Runs as EC2 userdata on worker node(s).
# Retrieves K3s join token from SSM and joins the cluster.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail
exec > >(tee /var/log/safecity-bootstrap.log) 2>&1

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity K3s Worker Bootstrap — $(date)"
echo "═══════════════════════════════════════════════════════"

export DEBIAN_FRONTEND=noninteractive
SC_MASTER_IP="${master_private_ip}"
SC_REGION="${aws_region}"
SC_PROJECT="${project_name}"

# ── System Updates ──────────────────────────────────────────────
echo "[1/4] Updating system packages …"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl wget jq unzip awscli

# ── Install Docker ──────────────────────────────────────────────
echo "[2/4] Installing Docker …"
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# ── Wait for K3s Token in SSM ───────────────────────────────────
echo "[3/4] Waiting for K3s join token from master …"
K3S_JOIN_TOKEN=""
for i in $(seq 1 60); do
    K3S_JOIN_TOKEN=$(aws ssm get-parameter \
        --name "/$SC_PROJECT/k3s-token" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region "$SC_REGION" 2>/dev/null || true)
    if [ -n "$K3S_JOIN_TOKEN" ] && [ "$K3S_JOIN_TOKEN" != "None" ]; then
        echo "Got K3s token from SSM."
        break
    fi
    echo "  Attempt $i/60 — token not yet available. Waiting 15s …"
    sleep 15
done

if [ -z "$K3S_JOIN_TOKEN" ] || [ "$K3S_JOIN_TOKEN" == "None" ]; then
    echo "ERROR: Failed to get K3s token after 15 minutes."
    exit 1
fi

# ── Join K3s Cluster ────────────────────────────────────────────
echo "[4/4] Joining K3s cluster …"
curl -sfL https://get.k3s.io | K3S_URL="https://$SC_MASTER_IP:6443" K3S_TOKEN="$K3S_JOIN_TOKEN" sh -s - agent \
    --node-name "$SC_PROJECT-worker-1"

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity Worker Bootstrap COMPLETE — $(date)"
echo "  Joined cluster at $SC_MASTER_IP:6443"
echo "═══════════════════════════════════════════════════════"
