from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app


def test_app_starts_and_exposes_openapi_schema():
    with TestClient(app) as client:
        response = client.get("/openapi.json")
        assert response.status_code == 200
        assert response.json()["info"]["title"] == "Sales CRM API"


def test_settings_default_to_development():
    settings = get_settings()
    assert settings.environment == "development"
    assert settings.is_production is False
