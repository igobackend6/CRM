from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import app.api.internal as internal_module
from app.main import app

WORKSPACE_ID = str(uuid4())
MEMBER_ID = str(uuid4())


@pytest.fixture
def client():
    return TestClient(app)


def _webhook_payload(**record):
    base = {
        "id": str(uuid4()),
        "workspace_id": WORKSPACE_ID,
        "recipient_member_id": MEMBER_ID,
        "type": "lead_assigned",
        "title": "Lead assigned to you",
        "body": "Acme Corp",
        "related_entity_type": "lead",
        "related_entity_id": str(uuid4()),
    }
    base.update(record)
    return {"type": "INSERT", "table": "notifications", "record": base}


def test_404_when_no_webhook_secret_is_configured(client, monkeypatch):
    monkeypatch.setattr(internal_module.get_settings(), "internal_webhook_secret", None, raising=False)
    r = client.post("/internal/push/notification", json=_webhook_payload())
    assert r.status_code == 404


def test_401_on_a_wrong_secret(client, monkeypatch):
    monkeypatch.setattr(internal_module.get_settings(), "internal_webhook_secret", "right-secret", raising=False)
    r = client.post("/internal/push/notification", json=_webhook_payload(), headers={"x-webhook-secret": "wrong"})
    assert r.status_code == 401


def test_202_and_dispatches_with_the_right_secret(client, monkeypatch):
    monkeypatch.setattr(internal_module.get_settings(), "internal_webhook_secret", "right-secret", raising=False)
    calls = []
    monkeypatch.setattr(
        internal_module, "push_to_member",
        lambda ws, member, **kw: calls.append({"ws": str(ws), "member": member, **kw}),
    )

    r = client.post(
        "/internal/push/notification",
        json=_webhook_payload(),
        headers={"x-webhook-secret": "right-secret"},
    )

    assert r.status_code == 202
    assert len(calls) == 1
    assert calls[0]["member"] == MEMBER_ID
    assert calls[0]["title"] == "Lead assigned to you"
    assert calls[0]["data"]["type"] == "lead_assigned"


def test_ignores_a_payload_missing_the_recipient(client, monkeypatch):
    monkeypatch.setattr(internal_module.get_settings(), "internal_webhook_secret", "right-secret", raising=False)
    calls = []
    monkeypatch.setattr(internal_module, "push_to_member", lambda *a, **k: calls.append(1))

    payload = _webhook_payload()
    del payload["record"]["recipient_member_id"]
    r = client.post("/internal/push/notification", json=payload, headers={"x-webhook-secret": "right-secret"})

    assert r.status_code == 202
    assert r.json()["status"] == "ignored"
    assert calls == []
