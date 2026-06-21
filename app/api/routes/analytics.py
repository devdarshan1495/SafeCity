"""
SafeCity API — Analytics Routes
Aggregation endpoints: summary stats, threat assessment, trend data.
"""

from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from database import get_db
from models import (
    Incident, Alert, SensorReading,
    AnalyticsSummary, ThreatAssessment,
    AlertCreate, AlertResponse,
)
from services.threat_engine import compute_overall_threat

router = APIRouter(prefix="/api/analytics", tags=["Analytics"])

_ACTIVE_STATUSES = {"reported", "dispatched", "responding"}


@router.get("/summary", response_model=AnalyticsSummary)
def get_summary(db: Session = Depends(get_db)):
    """City-wide incident analytics summary."""
    total = db.query(func.count(Incident.id)).scalar()
    active = (
        db.query(func.count(Incident.id))
        .filter(Incident.status.in_(_ACTIVE_STATUSES))
        .scalar()
    )
    resolved = (
        db.query(func.count(Incident.id))
        .filter(Incident.status.in_({"resolved", "closed"}))
        .scalar()
    )

    # By severity
    sev_rows = (
        db.query(Incident.severity, func.count(Incident.id))
        .group_by(Incident.severity)
        .all()
    )
    by_severity = {row[0]: row[1] for row in sev_rows}

    # By type
    type_rows = (
        db.query(Incident.incident_type, func.count(Incident.id))
        .group_by(Incident.incident_type)
        .all()
    )
    by_type = {row[0]: row[1] for row in type_rows}

    # By zone
    zone_rows = (
        db.query(Incident.zone, func.count(Incident.id))
        .filter(Incident.zone.isnot(None))
        .group_by(Incident.zone)
        .all()
    )
    by_zone = {row[0]: row[1] for row in zone_rows}

    # Average response time (for resolved incidents)
    resolved_incidents = (
        db.query(Incident)
        .filter(
            Incident.resolved_at.isnot(None),
            Incident.reported_at.isnot(None),
        )
        .all()
    )
    if resolved_incidents:
        deltas = [
            (inc.resolved_at - inc.reported_at).total_seconds() / 60.0
            for inc in resolved_incidents
        ]
        avg_response = round(sum(deltas) / len(deltas), 1)
    else:
        avg_response = None

    # Threat level
    threat = compute_overall_threat(db)

    return AnalyticsSummary(
        total_incidents=total,
        active_incidents=active,
        resolved_incidents=resolved,
        by_severity=by_severity,
        by_type=by_type,
        by_zone=by_zone,
        avg_response_time_minutes=avg_response,
        threat_level=threat["overall_level"],
        threat_score=threat["score"],
    )


@router.get("/threats", response_model=ThreatAssessment)
def get_threat_assessment(db: Session = Depends(get_db)):
    """Full threat assessment with zone-level breakdown."""
    return compute_overall_threat(db)


@router.get("/alerts")
def list_alerts(
    severity: Optional[str] = None,
    acknowledged: Optional[bool] = None,
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """List system alerts."""
    query = db.query(Alert)
    if severity:
        query = query.filter(Alert.severity == severity)
    if acknowledged is not None:
        query = query.filter(Alert.is_acknowledged == acknowledged)
    return query.order_by(Alert.created_at.desc()).limit(limit).all()


@router.post("/alerts", response_model=AlertResponse, status_code=201)
def create_alert(payload: AlertCreate, db: Session = Depends(get_db)):
    """Create a new alert."""
    alert = Alert(
        incident_id=payload.incident_id,
        alert_type=payload.alert_type.value,
        severity=payload.severity.value,
        message=payload.message,
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)
    return alert


@router.put("/alerts/{alert_id}/acknowledge")
def acknowledge_alert(alert_id: str, db: Session = Depends(get_db)):
    """Acknowledge an alert."""
    alert = db.query(Alert).filter(Alert.id == alert_id).first()
    if not alert:
        return {"error": "Alert not found"}, 404
    alert.is_acknowledged = True
    db.commit()
    return {"status": "acknowledged", "alert_id": alert_id}


@router.get("/sensors")
def list_sensor_readings(
    zone: Optional[str] = None,
    sensor_type: Optional[str] = None,
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """List latest sensor readings."""
    query = db.query(SensorReading)
    if zone:
        query = query.filter(SensorReading.zone == zone)
    if sensor_type:
        query = query.filter(SensorReading.sensor_type == sensor_type)
    return query.order_by(SensorReading.timestamp.desc()).limit(limit).all()


@router.get("/zones")
def zone_summary(db: Session = Depends(get_db)):
    """Per-zone incident summary."""
    zones = (
        db.query(Incident.zone, func.count(Incident.id))
        .filter(Incident.zone.isnot(None))
        .group_by(Incident.zone)
        .all()
    )
    result = []
    for zone_name, count in zones:
        active = (
            db.query(func.count(Incident.id))
            .filter(Incident.zone == zone_name, Incident.status.in_(_ACTIVE_STATUSES))
            .scalar()
        )
        result.append({
            "zone": zone_name,
            "total_incidents": count,
            "active_incidents": active,
        })
    return sorted(result, key=lambda x: x["active_incidents"], reverse=True)
