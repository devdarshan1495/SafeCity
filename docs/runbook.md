# SafeCity — Operational Runbook

## Quick Reference

| Service          | URL                              | Credentials          |
|-----------------|----------------------------------|----------------------|
| Dashboard        | `http://<MASTER_IP>:30080`       | —                    |
| API              | `http://<MASTER_IP>:30000`       | —                    |
| API Docs         | `http://<MASTER_IP>:30000/docs`  | —                    |
| Grafana          | `http://<MASTER_IP>:30030`       | admin / safecity     |
| Prometheus       | `http://<MASTER_IP>:30090`       | —                    |
| Jenkins          | `http://<MASTER_IP>:8080`        | See initial password |
| Vault            | `http://<MASTER_IP>:30082`       | Token: safecity-root-token |

## Infrastructure Provisioning

### Deploy Infrastructure
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Get Access Info
```bash
terraform output
```

### SSH into Nodes
```bash
# Master
ssh -i ~/Downloads/DevAnalytics.pem ubuntu@$(terraform output -raw master_public_ip)

# Worker
ssh -i ~/Downloads/DevAnalytics.pem ubuntu@$(terraform output -raw worker_public_ip)
```

### Tear Down (STOPS ALL CHARGES)
```bash
cd terraform
terraform destroy
```

## Deploying the Application

### First-time Setup (on master node)
```bash
# 1. Login to ECR
./ecr-login.sh

# 2. Clone repo and build images
git clone <repo-url> /home/ubuntu/safecity
cd /home/ubuntu/safecity

# 3. Build and push to ECR
ECR_REGISTRY=$(aws ecr describe-repositories --query 'repositories[0].repositoryUri' --output text | cut -d/ -f1)

docker build -t ${ECR_REGISTRY}/safecity-api:latest app/api/
docker build -t ${ECR_REGISTRY}/safecity-dashboard:latest app/dashboard/
docker push ${ECR_REGISTRY}/safecity-api:latest
docker push ${ECR_REGISTRY}/safecity-dashboard:latest

# 4. Update K8s manifests with ECR image URLs
sed -i "s|SAFECITY_API_IMAGE|${ECR_REGISTRY}/safecity-api:latest|g" kubernetes/app/api-deployment.yaml
sed -i "s|SAFECITY_DASHBOARD_IMAGE|${ECR_REGISTRY}/safecity-dashboard:latest|g" kubernetes/app/dashboard-deployment.yaml

# 5. Deploy everything
kubectl apply -f kubernetes/namespaces.yaml
kubectl apply -f kubernetes/app/
kubectl apply -f kubernetes/monitoring/
kubectl apply -f kubernetes/logging/
kubectl apply -f kubernetes/vault/
kubectl apply -f kubernetes/network-policies/
```

### Check Deployment Status
```bash
kubectl get pods -A
kubectl get svc -A
```

## Common Operations

### View Logs
```bash
# API logs
kubectl logs -n safecity -l app=safecity-api --tail=100 -f

# Dashboard logs
kubectl logs -n safecity -l app=safecity-dashboard --tail=100 -f

# All pods in a namespace
kubectl logs -n safecity --all-containers --tail=50
```

### Scale Application
```bash
# Manual scale
kubectl scale deployment safecity-api -n safecity --replicas=5

# Check HPA status
kubectl get hpa -n safecity
```

### Rolling Update
```bash
# Update image
kubectl set image deployment/safecity-api api=<new-image> -n safecity

# Watch rollout
kubectl rollout status deployment/safecity-api -n safecity

# Rollback if issues
kubectl rollout undo deployment/safecity-api -n safecity
```

### Jenkins Initial Password
```bash
# On master node
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

## Troubleshooting

### Pod Not Starting
```bash
kubectl describe pod <pod-name> -n safecity
kubectl logs <pod-name> -n safecity --previous
```

### Database Connection Issues
```bash
kubectl exec -it -n safecity $(kubectl get pods -n safecity -l app=postgres -o name) -- psql -U safecity
```

### Node Issues
```bash
kubectl describe node <node-name>
kubectl top nodes
kubectl top pods -n safecity
```

## Backup & Recovery

### Manual Backup
```bash
./scripts/backup.sh
```

### Restore from Backup
```bash
# List available backups
./scripts/restore.sh

# Restore specific backup
./scripts/restore.sh 20260621-143000
```

### Chaos Testing
```bash
./scripts/simulate-outage.sh all
```

## Health Verification
```bash
./scripts/health-check.sh <MASTER_IP>
```
