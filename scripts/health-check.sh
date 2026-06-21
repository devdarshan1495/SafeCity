#!/bin/bash
# ── SafeCity — Health Check Script ───────────────────────────────
# Verifies all platform components are running correctly.
# Usage: ./health-check.sh [master-ip]
# ─────────────────────────────────────────────────────────────────
set -uo pipefail

MASTER_IP="${1:-localhost}"

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity Platform Health Check"
echo "  Target: ${MASTER_IP}"
echo "═══════════════════════════════════════════════════════"
echo ""

PASS=0
FAIL=0

check() {
    local name="$1"
    local url="$2"
    local expected="${3:-200}"

    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    if [ "$STATUS" = "$expected" ]; then
        echo "  ✓  ${name} — HTTP ${STATUS}"
        PASS=$((PASS + 1))
    else
        echo "  ✗  ${name} — HTTP ${STATUS} (expected ${expected})"
        FAIL=$((FAIL + 1))
    fi
}

echo "── Application Services ────────────────────────────────"
check "SafeCity API        " "http://${MASTER_IP}:30000/health"
check "SafeCity Dashboard  " "http://${MASTER_IP}:30080/health"
check "API Docs (Swagger)  " "http://${MASTER_IP}:30000/docs"

echo ""
echo "── Monitoring Stack ────────────────────────────────────"
check "Prometheus          " "http://${MASTER_IP}:30090/-/ready"
check "Grafana             " "http://${MASTER_IP}:30030/api/health"

echo ""
echo "── Secrets Management ──────────────────────────────────"
check "Vault               " "http://${MASTER_IP}:30082/v1/sys/health"

echo ""
echo "── Kubernetes Cluster ──────────────────────────────────"
if command -v kubectl &> /dev/null; then
    echo "  Nodes:"
    kubectl get nodes 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "  Pods (safecity):"
    kubectl get pods -n safecity 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "  Pods (monitoring):"
    kubectl get pods -n monitoring 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "  Pods (logging):"
    kubectl get pods -n logging 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "  Pods (vault):"
    kubectl get pods -n vault 2>/dev/null | sed 's/^/    /'
else
    echo "  kubectl not available — skipping cluster checks."
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "═══════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
