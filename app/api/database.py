"""
SafeCity API — Database setup
SQLAlchemy engine, session factory, and base class.
Supports PostgreSQL (production) and SQLite (local dev).
"""

import logging
import time

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from sqlalchemy.exc import OperationalError
from config import settings

logger = logging.getLogger("safecity")

_url = settings.DATABASE_URL

# Normalize Postgres URL variants
if _url.startswith("postgres://"):
    _url = _url.replace("postgres://", "postgresql://", 1)

# SQLite needs check_same_thread=False for FastAPI's threaded usage
connect_args = {}
if _url.startswith("sqlite"):
    connect_args = {"check_same_thread": False}

engine = create_engine(_url, connect_args=connect_args, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    """FastAPI dependency — yields a DB session per request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def wait_for_db(max_retries=30, delay=2):
    """Wait for the database to become available with retries."""
    for attempt in range(1, max_retries + 1):
        try:
            conn = engine.connect()
            conn.close()
            logger.info("Database connection established.")
            return
        except OperationalError as e:
            logger.warning(
                "Database not ready (attempt %d/%d): %s",
                attempt, max_retries, e,
            )
            time.sleep(delay)
    raise RuntimeError(
        f"Could not connect to database after {max_retries} attempts."
    )


def init_db():
    """Create all tables. Called once at startup."""
    wait_for_db()
    Base.metadata.create_all(bind=engine)
