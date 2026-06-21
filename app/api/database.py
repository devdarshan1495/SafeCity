"""
SafeCity API — Database setup
SQLAlchemy engine, session factory, and base class.
Supports PostgreSQL (production) and SQLite (local dev).
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from config import settings


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


def init_db():
    """Create all tables. Called once at startup."""
    Base.metadata.create_all(bind=engine)
