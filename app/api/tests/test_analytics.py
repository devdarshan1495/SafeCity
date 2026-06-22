"""
SafeCity API — Analytics Endpoint Tests
"""


class TestAnalytics:
    INCIDENT = {
        "title": "Analytics test incident",
        "severity": "high",
        "incident_type": "crime",
        "zone": "Zone-A",
        "reporter": "CI Test",
    }

    def test_summary_empty(self, client):
        resp = client.get("/api/analytics/summary")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_incidents"] == 0
        assert data["active_incidents"] == 0

    def test_summary_with_data(self, client):
        client.post("/api/incidents", json=self.INCIDENT)
        resp = client.get("/api/analytics/summary")
        data = resp.json()
        assert data["total_incidents"] == 1
        assert data["active_incidents"] == 1
        assert data["by_severity"]["high"] == 1

    def test_threat_assessment(self, client):
        resp = client.get("/api/analytics/threats")
        assert resp.status_code == 200
        data = resp.json()
        assert "overall_level" in data
        assert "score" in data

    def test_alerts(self, client):
        resp = client.post(
            "/api/analytics/alerts",
            json={"alert_type": "system", "severity": "medium", "message": "Test alert"},
        )
        assert resp.status_code == 201
        resp = client.get("/api/analytics/alerts")
        assert resp.status_code == 200
        assert len(resp.json()) >= 1

    def test_zones(self, client):
        client.post("/api/incidents", json=self.INCIDENT)
        resp = client.get("/api/analytics/zones")
        assert resp.status_code == 200
        zones = resp.json()
        assert len(zones) >= 1
        assert any(z["zone"] == "Zone-A" for z in zones)
