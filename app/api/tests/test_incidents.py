"""
SafeCity API — Incident CRUD Tests
"""


class TestIncidents:
    SAMPLE = {
        "title": "Test incident",
        "description": "A test incident for CI",
        "severity": "high",
        "incident_type": "crime",
        "latitude": 19.076,
        "longitude": 72.8777,
        "address": "Test Location",
        "zone": "Zone-Test",
        "reporter": "CI Test",
    }

    def test_create_incident(self, client):
        resp = client.post("/api/incidents", json=self.SAMPLE)
        assert resp.status_code == 201
        data = resp.json()
        assert data["title"] == self.SAMPLE["title"]
        assert data["severity"] == "high"
        assert data["status"] == "reported"
        assert "id" in data

    def test_list_incidents(self, client):
        client.post("/api/incidents", json=self.SAMPLE)
        resp = client.get("/api/incidents")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) >= 1

    def test_list_incidents_filter_by_severity(self, client):
        client.post("/api/incidents", json=self.SAMPLE)
        resp = client.get("/api/incidents?severity=high")
        assert resp.status_code == 200
        assert len(resp.json()) >= 1
        resp = client.get("/api/incidents?severity=low")
        assert resp.status_code == 200
        assert len(resp.json()) == 0

    def test_get_incident_by_id(self, client):
        resp = client.post("/api/incidents", json=self.SAMPLE)
        created = resp.json()
        resp = client.get(f"/api/incidents/{created['id']}")
        assert resp.status_code == 200
        assert resp.json()["id"] == created["id"]

    def test_get_incident_not_found(self, client):
        resp = client.get("/api/incidents/nonexistent-id")
        assert resp.status_code == 404

    def test_update_incident(self, client):
        resp = client.post("/api/incidents", json=self.SAMPLE)
        created = resp.json()
        resp = client.put(
            f"/api/incidents/{created['id']}",
            json={"status": "resolved"},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "resolved"
        assert resp.json()["resolved_at"] is not None

    def test_delete_incident(self, client):
        resp = client.post("/api/incidents", json=self.SAMPLE)
        created = resp.json()
        resp = client.delete(f"/api/incidents/{created['id']}")
        assert resp.status_code == 204
        resp = client.get(f"/api/incidents/{created['id']}")
        assert resp.status_code == 404

    def test_count_incidents(self, client):
        client.post("/api/incidents", json=self.SAMPLE)
        client.post("/api/incidents", json={**self.SAMPLE, "title": "Second"})
        resp = client.get("/api/incidents/count")
        assert resp.status_code == 200
        assert resp.json()["count"] == 2
