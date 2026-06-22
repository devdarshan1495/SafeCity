"""
SafeCity API — Health Endpoint Tests
"""


class TestHealth:
    def test_health_returns_ok(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "healthy"
        assert "SafeCity" in data["service"]

    def test_ready_with_db(self, client):
        resp = client.get("/ready")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ready"
        assert data["database"] == "connected"

    def test_root_returns_links(self, client):
        resp = client.get("/")
        assert resp.status_code == 200
        data = resp.json()
        assert "docs" in data
        assert "health" in data
        assert "metrics" in data
