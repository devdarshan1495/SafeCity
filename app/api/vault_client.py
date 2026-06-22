"""
SafeCity API — Vault Client
Fetches secrets from HashiCorp Vault at startup with retries.
"""

import logging
import time
from typing import Optional

import hvac

from config import settings

logger = logging.getLogger("safecity")


def vault_available() -> bool:
    return bool(settings.VAULT_ADDR and settings.VAULT_TOKEN)


def _wait_for_vault(client: hvac.Client, max_retries: int = 6, delay: int = 5) -> bool:
    """Wait until Vault is reachable and seeded with our secrets."""
    for attempt in range(1, max_retries + 1):
        try:
            if client.is_authenticated():
                client.secrets.kv.v2.read_secret_version(
                    path="safecity/database", mount_point="secret"
                )
                logger.info("Vault is reachable and seeded.")
                return True
        except Exception:
            pass
        logger.warning(
            "Vault not ready yet (attempt %d/%d) …", attempt, max_retries
        )
        time.sleep(delay)
    return False


def fetch_secrets() -> dict:
    """Fetch all SafeCity secrets from Vault. Returns a flat dict."""
    if not vault_available():
        logger.info("Vault not configured — skipping secret fetch.")
        return {}

    client = hvac.Client(
        url=settings.VAULT_ADDR,
        token=settings.VAULT_TOKEN,
    )

    if not client.is_authenticated():
        logger.warning("Vault authentication failed — falling back to env vars.")
        return {}

    if not _wait_for_vault(client):
        logger.warning("Vault not ready after retries — falling back to env vars.")
        return {}

    secrets = {}

    paths = [
        "safecity/database",
        "safecity/api",
        "safecity/redis",
    ]

    for path in paths:
        try:
            data = client.secrets.kv.v2.read_secret_version(
                path=path, mount_point="secret"
            )
            secrets.update(data["data"]["data"])
            logger.info("Fetched secrets from secret/%s", path)
        except Exception as exc:
            logger.warning("Failed to read secret/%s from Vault: %s", path, exc)

    return secrets


def build_database_url(secrets: dict) -> Optional[str]:
    """Build a DATABASE_URL from Vault-stored DB credentials."""
    required = ["username", "password", "host", "port", "dbname"]
    if not all(k in secrets for k in required):
        return None
    return (
        f"postgresql://{secrets['username']}:{secrets['password']}"
        f"@{secrets['host']}:{secrets['port']}/{secrets['dbname']}"
    )
