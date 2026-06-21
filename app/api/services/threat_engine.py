"""
SafeCity — Threat Engine
Simulated predictive threat detection.
Computes a threat score (0–100) per zone and overall based on current incidents.
"""

from sqlalchemy.orm import Session
from sqlalchemy import func
from models import Incident, SeverityLevel


# Severity weights for threat scoring
_SEVERITY_WEIGHTS = {
    "critical": 25,
    "high": 15,
    "medium": 8,
    "low": 3,
}

# Incident type multipliers (some types are more threatening)
_TYPE_MULTIPLIERS = {
    "crime": 1.5,
    "cyber": 1.4,
    "fire": 1.3,
    "medical": 1.0,
    "traffic": 0.8,
    "infrastructure": 1.1,
    "environmental": 0.9,
}

_ACTIVE_STATUSES = {"reported", "dispatched", "responding"}


def compute_zone_threat(db: Session, zone: str) -> dict:
    """Compute a threat score for a specific zone."""
    incidents = (
        db.query(Incident)
        .filter(Incident.zone == zone, Incident.status.in_(_ACTIVE_STATUSES))
        .all()
    )

    if not incidents:
        return {"zone": zone, "score": 0.0, "level": "low", "active_incidents": 0}

    raw_score = 0.0
    for inc in incidents:
        weight = _SEVERITY_WEIGHTS.get(inc.severity, 5)
        multiplier = _TYPE_MULTIPLIERS.get(inc.incident_type, 1.0)
        raw_score += weight * multiplier

    # Normalize to 0–100 (cap at 100)
    score = min(round(raw_score, 1), 100.0)
    level = _score_to_level(score)

    return {
        "zone": zone,
        "score": score,
        "level": level,
        "active_incidents": len(incidents),
    }


def compute_overall_threat(db: Session) -> dict:
    """Compute city-wide threat assessment."""
    # Get all distinct zones with active incidents
    zones = (
        db.query(Incident.zone)
        .filter(Incident.status.in_(_ACTIVE_STATUSES))
        .distinct()
        .all()
    )
    zone_names = [z[0] for z in zones if z[0]]

    zone_assessments = [compute_zone_threat(db, z) for z in zone_names]

    # Overall score = weighted average of zone scores
    if zone_assessments:
        total_score = sum(z["score"] for z in zone_assessments)
        overall_score = min(round(total_score / max(len(zone_assessments), 1), 1), 100.0)
    else:
        overall_score = 0.0

    overall_level = _score_to_level(overall_score)

    # Contributing factors
    factors = _identify_factors(db)

    # Recommendations
    recommendations = _generate_recommendations(overall_level, factors)

    return {
        "overall_level": overall_level,
        "score": overall_score,
        "zones": zone_assessments,
        "contributing_factors": factors,
        "recommendations": recommendations,
    }


def _score_to_level(score: float) -> str:
    if score >= 70:
        return "critical"
    elif score >= 45:
        return "high"
    elif score >= 20:
        return "medium"
    return "low"


def _identify_factors(db: Session) -> list[str]:
    """Identify top contributing factors to the current threat level."""
    factors = []

    critical_count = (
        db.query(func.count(Incident.id))
        .filter(Incident.severity == "critical", Incident.status.in_(_ACTIVE_STATUSES))
        .scalar()
    )
    if critical_count > 0:
        factors.append(f"{critical_count} critical incident(s) currently active")

    crime_count = (
        db.query(func.count(Incident.id))
        .filter(Incident.incident_type == "crime", Incident.status.in_(_ACTIVE_STATUSES))
        .scalar()
    )
    if crime_count >= 2:
        factors.append(f"Elevated crime activity ({crime_count} active reports)")

    cyber_count = (
        db.query(func.count(Incident.id))
        .filter(Incident.incident_type == "cyber", Incident.status.in_(_ACTIVE_STATUSES))
        .scalar()
    )
    if cyber_count > 0:
        factors.append(f"Active cyber threat(s) detected ({cyber_count})")

    unassigned = (
        db.query(func.count(Incident.id))
        .filter(Incident.assigned_to.is_(None), Incident.status.in_(_ACTIVE_STATUSES))
        .scalar()
    )
    if unassigned > 2:
        factors.append(f"{unassigned} incidents awaiting responder assignment")

    if not factors:
        factors.append("No significant threat factors identified")

    return factors


def _generate_recommendations(level: str, factors: list[str]) -> list[str]:
    """Generate actionable recommendations based on threat level."""
    recs = []

    if level in ("critical", "high"):
        recs.append("Increase patrol density in high-risk zones")
        recs.append("Activate emergency response coordination center")
    if level == "critical":
        recs.append("Consider issuing public safety advisory")
        recs.append("Engage inter-agency mutual aid agreements")
    if any("cyber" in f.lower() for f in factors):
        recs.append("Isolate affected network segments and engage CSIRT")
    if any("unassigned" in f.lower() or "awaiting" in f.lower() for f in factors):
        recs.append("Reassign available units to unattended incidents")
    if level == "low":
        recs.append("Maintain standard patrol operations")
        recs.append("Continue routine monitoring")

    return recs
