"""
SafeCity API — Database setup
SQLAlchemy engine, session factory, and base class.
Supports PostgreSQL (production) and SQLite (local dev).
"""

import logging
import time
from typing import Optional

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from sqlalchemy.exc import OperationalError
from config import settings

logger = logging.getLogger("safecity")


def _build_url() -> str:
    """Return the normalized database URL from settings."""
    url = settings.DATABASE_URL
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)
    return url


def _connect_args(url: str) -> dict:
    """Return connection args appropriate for the given URL."""
    if url.startswith("sqlite"):
        return {"check_same_thread": False}
    return {}


_url = _build_url()
_connect_args_val = _connect_args(_url)

engine = create_engine(_url, connect_args=_connect_args_val, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def reinitialize(url: Optional[str] = None):
    """Rebuild engine and session factory with a new database URL."""
    global engine, SessionLocal, _url, _connect_args_val
    if url:
        _url = url
    _url = _build_url()
    _connect_args_val = _connect_args(_url)
    engine = create_engine(_url, connect_args=_connect_args_val, pool_pre_ping=True)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    logger.info("Database engine reinitialized with URL: %s", _url)


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
