"""
SafeCity Dashboard — Route Tests
"""

from unittest.mock import patch


class TestRoutes:
    def test_health(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["status"] == "healthy"

    def test_index_renders(self, client):
        with patch("app.api_get") as mock:
            mock.return_value = {}
            resp = client.get("/")
        assert resp.status_code == 200
        assert b"SafeCity" in resp.data or b"Dashboard" in resp.data

    def test_incidents_page(self, client):
        with patch("app.api_get") as mock:
            mock.return_value = []
            resp = client.get("/incidents")
        assert resp.status_code == 200

    def test_analytics_page(self, client):
        with patch("app.api_get") as mock:
            mock.return_value = {}
            resp = client.get("/analytics")
        assert resp.status_code == 200

    def test_severity_color_filter(self, client):
        resp = client.get("/incidents?severity=critical")
        assert resp.status_code == 200

    def test_create_incident_form(self, client):
        resp = client.get("/incidents/new")
        assert resp.status_code == 200

    def test_create_incident_post(self, client):
        with patch("app.api_post") as mock:
            mock.return_value = {"id": "test-id"}
            resp = client.post("/incidents/new", data={
                "title": "Test",
                "severity": "high",
                "incident_type": "crime",
            }, follow_redirects=True)
        assert resp.status_code == 200
