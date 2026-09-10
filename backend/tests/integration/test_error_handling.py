from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.errors import register_exception_handlers
from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.main import app as real_app


def test_unknown_route_returns_404():
    client = TestClient(real_app)
    response = client.get("/does-not-exist")
    assert response.status_code == 404


def test_app_error_is_mapped_to_structured_json_response():
    app = FastAPI()
    register_exception_handlers(app)

    @app.get("/boom")
    async def boom():
        raise NotFoundError("widget 123 not found.")

    client = TestClient(app)
    response = client.get("/boom")

    assert response.status_code == 404
    assert response.json() == {"error_code": "not_found", "message": "widget 123 not found."}


def test_permission_denied_error_maps_to_403():
    app = FastAPI()
    register_exception_handlers(app)

    @app.get("/restricted")
    async def restricted():
        raise PermissionDeniedError("Missing permission: leads.delete")

    client = TestClient(app)
    response = client.get("/restricted")

    assert response.status_code == 403
    assert response.json()["error_code"] == "permission_denied"


def test_unhandled_exception_maps_to_generic_500_without_leaking_details():
    app = FastAPI()
    register_exception_handlers(app)

    @app.get("/crash")
    async def crash():
        raise ValueError("some internal detail that should not reach the client")

    client = TestClient(app, raise_server_exceptions=False)
    response = client.get("/crash")

    assert response.status_code == 500
    body = response.json()
    assert body["error_code"] == "internal_error"
    assert "some internal detail" not in body["message"]
