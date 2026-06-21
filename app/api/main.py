"""
SafeCity Public Safety API — Application Entrypoint

Starts the FastAPI server with:
  - CORS middleware
  - Prometheus metrics at /metrics
  - Database initialization + seed data
  - All route modules
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from config import settings
from database import init_db, SessionLocal
from services.event_processor import seed_database

# ─── Logging ──────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)
logger = logging.getLogger("safecity")


# ─── Lifespan (startup / shutdown) ───────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing database …")
    init_db()

    # Seed demo data
    db = SessionLocal()
    try:
        seed_database(db)
        logger.info("Demo data seeded successfully.")
    finally:
        db.close()

    logger.info("SafeCity API is ready.")
    yield
    logger.info("SafeCity API shutting down.")


# ─── App ──────────────────────────────────────────────────────────────

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Real-time urban public safety analytics platform",
    lifespan=lifespan,
)

# CORS — allow the dashboard and any dev origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Prometheus metrics on /metrics
Instrumentator().instrument(app).expose(app, endpoint="/metrics")


# ─── Routers ──────────────────────────────────────────────────────────

from routes.incidents import router as incidents_router
from routes.analytics import router as analytics_router
from routes.health import router as health_router

app.include_router(incidents_router)
app.include_router(analytics_router)
app.include_router(health_router)


# ─── Root ─────────────────────────────────────────────────────────────

@app.get("/", tags=["Root"])
def root():
    return {
        "service": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "docs": "/docs",
        "health": "/health",
        "metrics": "/metrics",
    }


# ─── Direct run ──────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=settings.DEBUG,
    )
