"""
SafeCity API — Health & Readiness Routes
Exposes /health and /ready for Kubernetes probes.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import text

from database import get_db
from config import settings

router = APIRouter(tags=["Health"])


@router.get("/health")
def health_check():
    """
    Liveness probe — returns 200 if the process is alive.
    Kubernetes uses this to decide whether to restart the container.
    """
    return {
        "status": "healthy",
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
    }


@router.get("/ready")
def readiness_check(db: Session = Depends(get_db)):
    """
    Readiness probe — returns 200 only if the app can serve traffic
    (i.e., the database is reachable).
    """
    try:
        db.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception as exc:
        db_status = f"error: {exc}"
        return {"status": "not_ready", "database": db_status}

    return {
        "status": "ready",
        "database": db_status,
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
    }
