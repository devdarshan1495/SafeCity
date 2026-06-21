"""
SafeCity API — ORM Models & Pydantic Schemas
Defines Incident, Alert, and SensorReading tables plus their API schemas.
"""

import enum
import uuid
from datetime import datetime
from typing import Optional, List, Dict

from sqlalchemy import (
    Column, String, Float, Text, DateTime, Boolean, ForeignKey, Integer,
)
from sqlalchemy.orm import relationship
from pydantic import BaseModel, Field

from database import Base


# ─── Enums ────────────────────────────────────────────────────────────

class SeverityLevel(str, enum.Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class IncidentType(str, enum.Enum):
    CRIME = "crime"
    FIRE = "fire"
    TRAFFIC = "traffic"
    MEDICAL = "medical"
    INFRASTRUCTURE = "infrastructure"
    CYBER = "cyber"
    ENVIRONMENTAL = "environmental"


class IncidentStatus(str, enum.Enum):
    REPORTED = "reported"
    DISPATCHED = "dispatched"
    RESPONDING = "responding"
    RESOLVED = "resolved"
    CLOSED = "closed"


class AlertType(str, enum.Enum):
    THREAT = "threat"
    ANOMALY = "anomaly"
    SYSTEM = "system"
    WEATHER = "weather"


class SensorType(str, enum.Enum):
    CAMERA = "camera"
    TEMPERATURE = "temperature"
    MOTION = "motion"
    AIR_QUALITY = "air_quality"
    NOISE = "noise"
    TRAFFIC = "traffic"


# ─── SQLAlchemy ORM Models ────────────────────────────────────────────

def _uuid():
    return str(uuid.uuid4())


class Incident(Base):
    __tablename__ = "incidents"

    id = Column(String(36), primary_key=True, default=_uuid)
    title = Column(String(255), nullable=False, index=True)
    description = Column(Text, nullable=True)
    severity = Column(String(20), nullable=False, index=True)
    incident_type = Column(String(30), nullable=False, index=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    address = Column(String(500), nullable=True)
    status = Column(String(20), nullable=False, default="reported", index=True)
    zone = Column(String(50), nullable=True, index=True)
    reported_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    resolved_at = Column(DateTime, nullable=True)
    reporter = Column(String(100), nullable=True)
    assigned_to = Column(String(100), nullable=True)

    alerts = relationship("Alert", back_populates="incident", cascade="all, delete-orphan")


class Alert(Base):
    __tablename__ = "alerts"

    id = Column(String(36), primary_key=True, default=_uuid)
    incident_id = Column(String(36), ForeignKey("incidents.id"), nullable=True)
    alert_type = Column(String(20), nullable=False)
    severity = Column(String(20), nullable=False)
    message = Column(Text, nullable=False)
    is_acknowledged = Column(Boolean, default=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    incident = relationship("Incident", back_populates="alerts")


class SensorReading(Base):
    __tablename__ = "sensor_readings"

    id = Column(String(36), primary_key=True, default=_uuid)
    sensor_id = Column(String(100), nullable=False, index=True)
    sensor_type = Column(String(30), nullable=False)
    value = Column(Float, nullable=False)
    unit = Column(String(20), nullable=True)
    zone = Column(String(50), nullable=True, index=True)
    timestamp = Column(DateTime, nullable=False, default=datetime.utcnow)


# ─── Pydantic Schemas (Request / Response) ────────────────────────────

class IncidentCreate(BaseModel):
    title: str
    description: Optional[str] = None
    severity: SeverityLevel
    incident_type: IncidentType
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    address: Optional[str] = None
    zone: Optional[str] = None
    reporter: Optional[str] = None


class IncidentUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    severity: Optional[SeverityLevel] = None
    status: Optional[IncidentStatus] = None
    assigned_to: Optional[str] = None
    resolved_at: Optional[datetime] = None


class IncidentResponse(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    severity: str
    incident_type: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    address: Optional[str] = None
    status: str
    zone: Optional[str] = None
    reported_at: datetime
    resolved_at: Optional[datetime] = None
    reporter: Optional[str] = None
    assigned_to: Optional[str] = None

    class Config:
        from_attributes = True


class AlertCreate(BaseModel):
    incident_id: Optional[str] = None
    alert_type: AlertType
    severity: SeverityLevel
    message: str


class AlertResponse(BaseModel):
    id: str
    incident_id: Optional[str] = None
    alert_type: str
    severity: str
    message: str
    is_acknowledged: bool
    created_at: datetime

    class Config:
        from_attributes = True


class AnalyticsSummary(BaseModel):
    total_incidents: int
    active_incidents: int
    resolved_incidents: int
    by_severity: Dict[str, int]
    by_type: Dict[str, int]
    by_zone: Dict[str, int]
    avg_response_time_minutes: Optional[float] = None
    threat_level: str
    threat_score: float


class ThreatAssessment(BaseModel):
    overall_level: str
    score: float
    zones: List[Dict]
    contributing_factors: List[str]
    recommendations: List[str]
