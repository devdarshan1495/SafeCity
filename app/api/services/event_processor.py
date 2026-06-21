"""
SafeCity — Event Processor & Data Seeder
Seeds the database with realistic demo incidents, alerts, and sensor readings
on first startup. Provides a background event simulation loop.
"""

import random
import uuid
from datetime import datetime, timedelta

from sqlalchemy.orm import Session
from models import Incident, Alert, SensorReading


# ─── Seed Data ────────────────────────────────────────────────────────

SEED_INCIDENTS = [
    {
        "title": "Armed Robbery in Progress — Zone 4",
        "description": "Two armed suspects reported inside a convenience store on MG Road. Hostages possible. Silent alarm triggered at 13:42 IST.",
        "severity": "critical",
        "incident_type": "crime",
        "latitude": 19.0760,
        "longitude": 72.8777,
        "address": "MG Road, Zone 4, Mumbai",
        "status": "responding",
        "zone": "Zone-4",
        "reporter": "Auto-Dispatch",
        "assigned_to": "Unit Alpha-7",
    },
    {
        "title": "Multi-Vehicle Collision — Highway NH48",
        "description": "Chain collision involving 4 vehicles near Andheri flyover. Two lanes blocked. Injuries reported. Medical and traffic units dispatched.",
        "severity": "high",
        "incident_type": "traffic",
        "latitude": 19.1136,
        "longitude": 72.8697,
        "address": "NH48, Andheri Flyover, Mumbai",
        "status": "dispatched",
        "zone": "Zone-2",
        "reporter": "Traffic Cam AI",
        "assigned_to": "Traffic Unit-3",
    },
    {
        "title": "Structure Fire — Residential Block, Sector 7",
        "description": "Fire reported on 4th floor of residential building. Evacuation underway. Three fire tenders dispatched.",
        "severity": "critical",
        "incident_type": "fire",
        "latitude": 19.0330,
        "longitude": 72.8440,
        "address": "Sector 7, Bandra West, Mumbai",
        "status": "responding",
        "zone": "Zone-7",
        "reporter": "Smoke Sensor Array",
        "assigned_to": "Fire Station-12",
    },
    {
        "title": "Cardiac Arrest — Public Market",
        "description": "62-year-old male collapsed at Crawford Market. Bystander CPR in progress. Ambulance ETA 4 minutes.",
        "severity": "high",
        "incident_type": "medical",
        "latitude": 18.9470,
        "longitude": 72.8340,
        "address": "Crawford Market, Fort, Mumbai",
        "status": "responding",
        "zone": "Zone-1",
        "reporter": "Citizen Report",
        "assigned_to": "Ambulance-9",
    },
    {
        "title": "Water Main Rupture — Industrial Zone",
        "description": "Major water main break flooding Mahakali Caves Road. Traffic diverted. Municipal crew notified.",
        "severity": "medium",
        "incident_type": "infrastructure",
        "latitude": 19.1285,
        "longitude": 72.8845,
        "address": "Mahakali Caves Rd, MIDC, Mumbai",
        "status": "reported",
        "zone": "Zone-3",
        "reporter": "IoT Pressure Sensor",
        "assigned_to": None,
    },
    {
        "title": "Suspicious Package — Metro Station",
        "description": "Unattended bag reported at Churchgate Metro entrance. Bomb squad alerted. 200m cordon established.",
        "severity": "high",
        "incident_type": "crime",
        "latitude": 18.9356,
        "longitude": 72.8274,
        "address": "Churchgate Station, Mumbai",
        "status": "dispatched",
        "zone": "Zone-1",
        "reporter": "CCTV Analytics",
        "assigned_to": "Bomb Disposal Unit-1",
    },
    {
        "title": "DDoS Attack on Traffic Management System",
        "description": "Distributed denial-of-service attack detected targeting smart traffic light controllers across Zone-5. Signal timing disrupted.",
        "severity": "critical",
        "incident_type": "cyber",
        "latitude": 19.0596,
        "longitude": 72.8295,
        "address": "Traffic Control Center, Worli, Mumbai",
        "status": "responding",
        "zone": "Zone-5",
        "reporter": "SIEM Alert",
        "assigned_to": "Cyber Response Team",
    },
    {
        "title": "Air Quality Index Spike — Industrial Area",
        "description": "AQI readings exceeding 350 in MIDC area. Possible chemical release from factory complex. Investigation initiated.",
        "severity": "medium",
        "incident_type": "environmental",
        "latitude": 19.1340,
        "longitude": 72.8900,
        "address": "MIDC Phase-2, Andheri East, Mumbai",
        "status": "reported",
        "zone": "Zone-3",
        "reporter": "AQ Sensor Network",
        "assigned_to": None,
    },
    {
        "title": "Missing Child Report — Zone 6",
        "description": "8-year-old female last seen at Juhu Beach at approximately 16:00 IST. Wearing red dress. Search operation mobilized.",
        "severity": "high",
        "incident_type": "crime",
        "latitude": 19.0883,
        "longitude": 72.8263,
        "address": "Juhu Beach, Mumbai",
        "status": "responding",
        "zone": "Zone-6",
        "reporter": "Citizen Report",
        "assigned_to": "Search Unit-4",
    },
    {
        "title": "Power Grid Failure — Eastern Suburbs",
        "description": "Transformer explosion at Ghatkopar substation. 50,000+ households without power. Repair crews mobilized. Estimated restoration: 4 hours.",
        "severity": "high",
        "incident_type": "infrastructure",
        "latitude": 19.0865,
        "longitude": 72.9080,
        "address": "MSEB Substation, Ghatkopar, Mumbai",
        "status": "dispatched",
        "zone": "Zone-8",
        "reporter": "SCADA System",
        "assigned_to": "MSEB Emergency Crew",
    },
    {
        "title": "Noise Violation — Construction Site",
        "description": "Construction noise exceeding 85dB after permitted hours in residential zone. Multiple citizen complaints filed.",
        "severity": "low",
        "incident_type": "environmental",
        "latitude": 19.0620,
        "longitude": 72.8350,
        "address": "Prabhadevi, Mumbai",
        "status": "reported",
        "zone": "Zone-5",
        "reporter": "Noise Sensor",
        "assigned_to": None,
    },
    {
        "title": "Minor Fender Bender — Parking Lot",
        "description": "Low-speed collision in Phoenix Mall parking lot. No injuries. Vehicles moved to side. Report filed for insurance.",
        "severity": "low",
        "incident_type": "traffic",
        "latitude": 19.0014,
        "longitude": 72.8277,
        "address": "Phoenix Mall, Lower Parel, Mumbai",
        "status": "resolved",
        "zone": "Zone-5",
        "reporter": "Security Guard",
        "assigned_to": "Traffic Constable",
    },
]

SEED_ALERTS = [
    {
        "alert_type": "threat",
        "severity": "high",
        "message": "Elevated crime rate detected in Zone-4 — 3 incidents in the past 2 hours. Consider increasing patrol density.",
    },
    {
        "alert_type": "anomaly",
        "severity": "medium",
        "message": "Anomalous traffic pattern on NH48 near Andheri — possible accident-related diversion required.",
    },
    {
        "alert_type": "system",
        "severity": "low",
        "message": "Prometheus scrape target 'node-exporter:9100' returned timeout after 10s. Investigating.",
    },
    {
        "alert_type": "weather",
        "severity": "high",
        "message": "IMD severe weather advisory: Heavy rainfall warning for Mumbai — potential flooding in low-lying Zones 1, 5, and 7.",
    },
    {
        "alert_type": "threat",
        "severity": "critical",
        "message": "Cyber threat intelligence: Active DDoS campaign targeting municipal infrastructure. All systems on heightened alert.",
    },
    {
        "alert_type": "anomaly",
        "severity": "medium",
        "message": "Unusual sensor reading cluster in Zone-3 — 4 air quality sensors reporting simultaneous spikes.",
    },
]

SEED_SENSORS = [
    ("CAM-001", "camera", 1.0, "active", "Zone-1"),
    ("CAM-002", "camera", 1.0, "active", "Zone-4"),
    ("TEMP-001", "temperature", 34.5, "°C", "Zone-3"),
    ("TEMP-002", "temperature", 31.2, "°C", "Zone-7"),
    ("MOT-001", "motion", 87.0, "detections/hr", "Zone-4"),
    ("AQ-001", "air_quality", 352.0, "AQI", "Zone-3"),
    ("AQ-002", "air_quality", 128.0, "AQI", "Zone-1"),
    ("NOISE-001", "noise", 88.5, "dB", "Zone-5"),
    ("NOISE-002", "noise", 52.0, "dB", "Zone-6"),
    ("TRAF-001", "traffic", 1245.0, "vehicles/hr", "Zone-2"),
    ("TRAF-002", "traffic", 890.0, "vehicles/hr", "Zone-8"),
    ("TRAF-003", "traffic", 2100.0, "vehicles/hr", "Zone-5"),
]


def seed_database(db: Session) -> None:
    """Populate the DB with demo data if it's empty."""
    existing = db.query(Incident).count()
    if existing > 0:
        return  # Already seeded

    now = datetime.utcnow()

    # Seed incidents with staggered times
    for i, data in enumerate(SEED_INCIDENTS):
        incident = Incident(
            id=str(uuid.uuid4()),
            reported_at=now - timedelta(minutes=random.randint(5, 180)),
            resolved_at=(now - timedelta(minutes=random.randint(1, 30))
                         if data["status"] == "resolved" else None),
            **data,
        )
        db.add(incident)
    db.flush()

    # Seed alerts
    all_incidents = db.query(Incident).all()
    for i, data in enumerate(SEED_ALERTS):
        alert = Alert(
            id=str(uuid.uuid4()),
            incident_id=all_incidents[i % len(all_incidents)].id if i < 3 else None,
            created_at=now - timedelta(minutes=random.randint(1, 60)),
            **data,
        )
        db.add(alert)

    # Seed sensor readings
    for sensor_id, sensor_type, value, unit, zone in SEED_SENSORS:
        reading = SensorReading(
            id=str(uuid.uuid4()),
            sensor_id=sensor_id,
            sensor_type=sensor_type,
            value=value,
            unit=unit,
            zone=zone,
            timestamp=now - timedelta(seconds=random.randint(0, 300)),
        )
        db.add(reading)

    db.commit()
