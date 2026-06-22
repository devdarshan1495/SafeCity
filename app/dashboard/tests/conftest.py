"""
SafeCity Dashboard — Test Fixtures
"""

import pytest
from app import app as flask_app


@pytest.fixture(scope="function")
def client():
    flask_app.config["TESTING"] = True
    flask_app.config["WTF_CSRF_ENABLED"] = False
    with flask_app.test_client() as c:
        yield c
