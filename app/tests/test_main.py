from fastapi.testclient import TestClient

from main import SERVICE_NAME, app

client = TestClient(app)


def test_root_returns_service_and_version(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "abc123")

    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {"service": SERVICE_NAME, "version": "abc123"}


def test_root_defaults_version_to_dev(monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)

    response = client.get("/")

    assert response.json()["version"] == "dev"


def test_health_returns_200():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
