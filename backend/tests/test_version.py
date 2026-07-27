from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_version_returns_required_fields():
    res = client.get("/api/version")
    assert res.status_code == 200
    body = res.json()
    assert {"service", "version", "git_sha", "image_digest", "environment"} <= body.keys()


def test_healthz():
    assert client.get("/api/healthz").json() == {"ok": True}
