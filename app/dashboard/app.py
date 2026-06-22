"""
SafeCity Dashboard — Flask Application
Minimalist public safety operations dashboard.
Fetches data from the SafeCity API and renders server-side templates.
"""

import os
import logging
from datetime import datetime

import time
import requests
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, Response
from prometheus_client import Counter, Histogram, generate_latest, REGISTRY

# ─── Configuration ───────────────────────────────────────────────────

API_URL = os.getenv("API_URL", "http://localhost:8000")
SECRET_KEY = os.getenv("SECRET_KEY", "safecity-dashboard-dev-key")

app = Flask(__name__)
app.secret_key = SECRET_KEY

# Prometheus metrics
requests_total = Counter("dashboard_requests_total", "Total dashboard requests", ["method", "endpoint"])
request_duration = Histogram("dashboard_request_duration_seconds", "Dashboard request duration", ["method", "endpoint"])

# ─── After-request instrumentation ────────────────────────────────

@app.before_request
def _start_timer():
    request._prom_start = time.time()

@app.after_request
def _instrument(response):
    requests_total.labels(method=request.method, endpoint=request.path).inc()
    dt = time.time() - request._prom_start if hasattr(request, "_prom_start") else 0
    request_duration.labels(method=request.method, endpoint=request.path).observe(dt)
    return response

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)
logger = logging.getLogger("dashboard")


# ─── Helpers ─────────────────────────────────────────────────────────

def api_get(path: str, params: dict = None):
    """GET request to the SafeCity API. Returns JSON or empty dict on failure."""
    try:
        resp = requests.get(f"{API_URL}{path}", params=params, timeout=5)
        resp.raise_for_status()
        return resp.json()
    except Exception as exc:
        logger.warning(f"API call failed: {path} — {exc}")
        return {}


def api_post(path: str, json_data: dict):
    try:
        resp = requests.post(f"{API_URL}{path}", json=json_data, timeout=5)
        resp.raise_for_status()
        return resp.json()
    except Exception as exc:
        logger.warning(f"API POST failed: {path} — {exc}")
        return None


def api_put(path: str, json_data: dict):
    try:
        resp = requests.put(f"{API_URL}{path}", json=json_data, timeout=5)
        resp.raise_for_status()
        return resp.json()
    except Exception as exc:
        logger.warning(f"API PUT failed: {path} — {exc}")
        return None


def api_delete(path: str):
    try:
        resp = requests.delete(f"{API_URL}{path}", timeout=5)
        return resp.status_code == 204
    except Exception as exc:
        logger.warning(f"API DELETE failed: {path} — {exc}")
        return False


# ─── Template Filters ────────────────────────────────────────────────

@app.template_filter("severity_color")
def severity_color(severity: str) -> str:
    return {
        "critical": "#dc2626",
        "high": "#ea580c",
        "medium": "#ca8a04",
        "low": "#16a34a",
    }.get(severity, "#6b7280")


@app.template_filter("status_color")
def status_color(status: str) -> str:
    return {
        "reported": "#6b7280",
        "dispatched": "#2563eb",
        "responding": "#ea580c",
        "resolved": "#16a34a",
        "closed": "#9ca3af",
    }.get(status, "#6b7280")


@app.template_filter("timeago")
def timeago_filter(dt_str):
    """Convert an ISO datetime string to a human-readable time-ago string."""
    if not dt_str:
        return "—"
    try:
        if isinstance(dt_str, str):
            # Handle various ISO formats
            dt_str = dt_str.replace("Z", "+00:00")
            dt = datetime.fromisoformat(dt_str).replace(tzinfo=None)
        else:
            dt = dt_str
        delta = datetime.utcnow() - dt
        seconds = int(delta.total_seconds())
        if seconds < 60:
            return f"{seconds}s ago"
        elif seconds < 3600:
            return f"{seconds // 60}m ago"
        elif seconds < 86400:
            return f"{seconds // 3600}h ago"
        else:
            return f"{seconds // 86400}d ago"
    except Exception:
        return str(dt_str)


# ─── Routes ──────────────────────────────────────────────────────────

@app.route("/")
def index():
    """Main dashboard — overview cards + recent incidents."""
    summary = api_get("/api/analytics/summary")
    incidents = api_get("/api/incidents", {"limit": 8})
    alerts = api_get("/api/analytics/alerts", {"limit": 5})
    zones = api_get("/api/analytics/zones")

    # Ensure we always have valid data for the template
    if not isinstance(incidents, list):
        incidents = []
    if not isinstance(alerts, list):
        alerts = []
    if not isinstance(zones, list):
        zones = []

    return render_template(
        "index.html",
        summary=summary,
        incidents=incidents,
        alerts=alerts,
        zones=zones,
        page="dashboard",
    )


@app.route("/incidents")
def incidents_page():
    """Full incidents list with filters."""
    severity = request.args.get("severity")
    incident_type = request.args.get("type")
    status = request.args.get("status")
    zone = request.args.get("zone")

    params = {"limit": 50}
    if severity:
        params["severity"] = severity
    if incident_type:
        params["incident_type"] = incident_type
    if status:
        params["status"] = status
    if zone:
        params["zone"] = zone

    incidents = api_get("/api/incidents", params)
    if not isinstance(incidents, list):
        incidents = []

    return render_template(
        "incidents.html",
        incidents=incidents,
        page="incidents",
        filters={"severity": severity, "type": incident_type, "status": status, "zone": zone},
    )


@app.route("/incidents/new", methods=["GET", "POST"])
def create_incident():
    """Create a new incident."""
    if request.method == "POST":
        data = {
            "title": request.form["title"],
            "description": request.form.get("description", ""),
            "severity": request.form["severity"],
            "incident_type": request.form["incident_type"],
            "address": request.form.get("address", ""),
            "zone": request.form.get("zone", ""),
            "reporter": request.form.get("reporter", "Dashboard User"),
        }
        # Parse optional lat/lng
        lat = request.form.get("latitude")
        lng = request.form.get("longitude")
        if lat:
            data["latitude"] = float(lat)
        if lng:
            data["longitude"] = float(lng)

        result = api_post("/api/incidents", data)
        if result:
            flash("Incident created successfully.", "success")
            return redirect(url_for("incidents_page"))
        else:
            flash("Failed to create incident.", "error")

    return render_template("create_incident.html", page="incidents")


@app.route("/analytics")
def analytics_page():
    """Charts and detailed analytics."""
    summary = api_get("/api/analytics/summary")
    threats = api_get("/api/analytics/threats")
    zones = api_get("/api/analytics/zones")
    sensors = api_get("/api/analytics/sensors", {"limit": 20})

    if not isinstance(zones, list):
        zones = []
    if not isinstance(sensors, list):
        sensors = []

    return render_template(
        "analytics.html",
        summary=summary,
        threats=threats,
        zones=zones,
        sensors=sensors,
        page="analytics",
    )


@app.route("/metrics")
def metrics():
    return Response(generate_latest(REGISTRY), mimetype="text/plain")

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": "SafeCity Dashboard"})


# ─── Run ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
