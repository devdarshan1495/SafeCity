#!/bin/bash
# ── SafeCity — Chaos / Outage Simulation ─────────────────────────
# Simulates various failure scenarios to test self-healing.
# Usage: ./simulate-outage.sh [pod-kill|node-drain|cpu-spike|all]
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

SCENARIO="${1:-all}"

echo "═══════════════════════════════════════════════════════"
echo "  SafeCity Chaos Test — Scenario: ${SCENARIO}"
echo "═══════════════════════════════════════════════════════"

# ── Scenario 1: Kill random pods ────────────────────────────────
run_pod_kill() {
    echo ""
    echo "── SCENARIO: Pod Kill ──────────────────────────────"
    echo "Killing a random SafeCity API pod …"

    POD=$(kubectl get pods -n safecity -l app=safecity-api -o jsonpath='{.items[0].metadata.name}')
    echo "  Target: $POD"
    kubectl delete pod "$POD" -n safecity --grace-period=0 --force 2>/dev/null

    echo "  Pod killed. Watching recovery …"
    sleep 5
    kubectl get pods -n safecity -l app=safecity-api
    echo ""
    echo "  Waiting for replacement pod to be ready …"
    kubectl wait --for=condition=ready pod -l app=safecity-api -n safecity --timeout=60s
    echo "  ✓ Recovery successful — new pod is ready."
}

# ── Scenario 2: Node drain (simulate node failure) ──────────────
run_node_drain() {
    echo ""
    echo "── SCENARIO: Node Drain ────────────────────────────"
    WORKER=$(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [ -z "$WORKER" ]; then
        echo "  No worker nodes found. Skipping."
        return
    fi

    echo "  Cordoning worker: $WORKER"
    kubectl cordon "$WORKER"

    echo "  Draining worker (evicting pods) …"
    kubectl drain "$WORKER" --ignore-daemonsets --delete-emptydir-data --force --timeout=60s 2>/dev/null || true

    echo "  Worker drained. Pods should reschedule to master."
    sleep 10
    kubectl get pods -n safecity -o wide

    echo ""
    echo "  Uncordoning worker: $WORKER"
    kubectl uncordon "$WORKER"
    echo "  ✓ Node back in rotation."
}

# ── Scenario 3: CPU spike (trigger HPA) ─────────────────────────
run_cpu_spike() {
    echo ""
    echo "── SCENARIO: CPU Spike (HPA Trigger) ───────────────"
    echo "  Sending 1000 rapid requests to API …"

    for i in $(seq 1 1000); do
        curl -s "http://localhost:30000/api/incidents" > /dev/null &
    done
    wait

    echo "  Request burst complete."
    echo "  Current HPA status:"
    kubectl get hpa -n safecity
    echo ""
    echo "  Watch HPA scaling:"
    echo "  → kubectl get hpa -n safecity --watch"
}

# ── Scenario 4: Dashboard pod kill ──────────────────────────────
run_dashboard_kill() {
    echo ""
    echo "── SCENARIO: Dashboard Pod Kill ────────────────────"
    POD=$(kubectl get pods -n safecity -l app=safecity-dashboard -o jsonpath='{.items[0].metadata.name}')
    echo "  Target: $POD"
    kubectl delete pod "$POD" -n safecity --grace-period=0 --force 2>/dev/null

    echo "  Waiting for recovery …"
    kubectl wait --for=condition=ready pod -l app=safecity-dashboard -n safecity --timeout=60s
    echo "  ✓ Dashboard recovered."
}

# ── Run scenarios ───────────────────────────────────────────────
case "$SCENARIO" in
    pod-kill)      run_pod_kill ;;
    node-drain)    run_node_drain ;;
    cpu-spike)     run_cpu_spike ;;
    dashboard)     run_dashboard_kill ;;
    all)
        run_pod_kill
        echo ""
        sleep 5
        run_dashboard_kill
        echo ""
        sleep 5
        run_node_drain
        echo ""
        sleep 5
        run_cpu_spike
        ;;
    *)
        echo "Usage: $0 [pod-kill|node-drain|cpu-spike|dashboard|all]"
        exit 1
        ;;
esac

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Chaos Test COMPLETE"
echo "  Final pod status:"
echo "═══════════════════════════════════════════════════════"
kubectl get pods -n safecity -o wide
