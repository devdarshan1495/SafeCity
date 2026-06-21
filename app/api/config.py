"""
SafeCity API — Configuration
Loads settings from environment variables with sensible defaults.
"""

import os


class Settings:
    APP_NAME: str = "SafeCity Public Safety API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = os.getenv("DEBUG", "false").lower() == "true"

    # Database
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL", "sqlite:///./safecity.db"
    )

    # Redis (for caching / event queue)
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")

    # API
    API_HOST: str = os.getenv("API_HOST", "0.0.0.0")
    API_PORT: int = int(os.getenv("API_PORT", "8000"))

    # Dashboard
    DASHBOARD_URL: str = os.getenv("DASHBOARD_URL", "http://localhost:5000")

    # Vault (optional)
    VAULT_ADDR: str = os.getenv("VAULT_ADDR", "")
    VAULT_TOKEN: str = os.getenv("VAULT_TOKEN", "")


settings = Settings()
