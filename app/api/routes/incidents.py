"""
SafeCity API — Incident Routes
Full CRUD for public safety incidents.
"""

from datetime import datetime
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from database import get_db
from models import (
    Incident, IncidentCreate, IncidentUpdate, IncidentResponse,
)

router = APIRouter(prefix="/api/incidents", tags=["Incidents"])


@router.get("", response_model=List[IncidentResponse])
def list_incidents(
    severity: Optional[str] = Query(None, description="Filter by severity"),
    incident_type: Optional[str] = Query(None, description="Filter by type"),
    status: Optional[str] = Query(None, description="Filter by status"),
    zone: Optional[str] = Query(None, description="Filter by zone"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """List incidents with optional filters."""
    query = db.query(Incident)

    if severity:
        query = query.filter(Incident.severity == severity)
    if incident_type:
        query = query.filter(Incident.incident_type == incident_type)
    if status:
        query = query.filter(Incident.status == status)
    if zone:
        query = query.filter(Incident.zone == zone)

    query = query.order_by(Incident.reported_at.desc())
    return query.offset(offset).limit(limit).all()


@router.get("/count")
def count_incidents(
    severity: Optional[str] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """Return incident counts (total, by status, by severity)."""
    query = db.query(Incident)
    if severity:
        query = query.filter(Incident.severity == severity)
    if status:
        query = query.filter(Incident.status == status)
    return {"count": query.count()}


@router.get("/{incident_id}", response_model=IncidentResponse)
def get_incident(incident_id: str, db: Session = Depends(get_db)):
    """Get a single incident by ID."""
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found")
    return incident


@router.post("", response_model=IncidentResponse, status_code=201)
def create_incident(payload: IncidentCreate, db: Session = Depends(get_db)):
    """Create a new incident."""
    incident = Incident(
        title=payload.title,
        description=payload.description,
        severity=payload.severity.value,
        incident_type=payload.incident_type.value,
        latitude=payload.latitude,
        longitude=payload.longitude,
        address=payload.address,
        zone=payload.zone,
        reporter=payload.reporter,
        status="reported",
        reported_at=datetime.utcnow(),
    )
    db.add(incident)
    db.commit()
    db.refresh(incident)
    return incident


@router.put("/{incident_id}", response_model=IncidentResponse)
def update_incident(
    incident_id: str, payload: IncidentUpdate, db: Session = Depends(get_db)
):
    """Update an existing incident."""
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found")

    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        if hasattr(value, "value"):  # Enum → string
            value = value.value
        setattr(incident, field, value)

    # Auto-set resolved_at when status changes to resolved/closed
    if payload.status and payload.status.value in ("resolved", "closed"):
        if not incident.resolved_at:
            incident.resolved_at = datetime.utcnow()

    db.commit()
    db.refresh(incident)
    return incident


@router.delete("/{incident_id}", status_code=204)
def delete_incident(incident_id: str, db: Session = Depends(get_db)):
    """Delete an incident."""
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found")
    db.delete(incident)
    db.commit()
