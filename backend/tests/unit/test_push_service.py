from uuid import uuid4

import app.services.push.service as push_module
from app.services.push import push_to_member
from tests.support.fake_supabase import FakeResponse, FakeSupabaseClient

WORKSPACE_ID = uuid4()
MEMBER_ID = str(uuid4())
PROFILE_ID = str(uuid4())


class _FakeSender:
    def __init__(self, results):
        self._results = dict(results)  # token -> bool
        self.sent = []

    def send(self, *, token, title, body, data):
        self.sent.append({"token": token, "title": title, "body": body, "data": data})
        return self._results.get(token, True)


def _client(tokens):
    return FakeSupabaseClient(
        table_responses={
            "workspace_members": FakeResponse(data={"profile_id": PROFILE_ID}),
            "device_tokens": FakeResponse(data=[{"id": str(uuid4()), "token": t, "platform": "android"} for t in tokens]),
        }
    )


def test_no_op_when_fcm_is_not_configured(monkeypatch):
    monkeypatch.setattr(push_module, "get_fcm_sender", lambda: None)
    sup = _client(["tok-a"])
    monkeypatch.setattr(push_module, "get_supabase_client", lambda: sup)

    push_to_member(WORKSPACE_ID, MEMBER_ID, title="Hi", body="there")

    # Never even looked up device tokens.
    assert "device_tokens" not in sup.table_calls


def test_no_op_when_service_role_client_is_unavailable(monkeypatch):
    monkeypatch.setattr(push_module, "get_fcm_sender", lambda: _FakeSender({}))
    monkeypatch.setattr(push_module, "get_supabase_client", lambda: None)

    push_to_member(WORKSPACE_ID, MEMBER_ID, title="Hi")  # must not raise


def test_sends_to_every_registered_device(monkeypatch):
    sender = _FakeSender({"tok-a": True, "tok-b": True})
    monkeypatch.setattr(push_module, "get_fcm_sender", lambda: sender)
    monkeypatch.setattr(push_module, "get_supabase_client", lambda: _client(["tok-a", "tok-b"]))

    push_to_member(WORKSPACE_ID, MEMBER_ID, title="Lead assigned to you", body="Acme Corp",
                   data={"type": "lead_assigned"})

    assert {s["token"] for s in sender.sent} == {"tok-a", "tok-b"}
    assert sender.sent[0]["title"] == "Lead assigned to you"
    assert sender.sent[0]["data"]["type"] == "lead_assigned"


def test_prunes_tokens_fcm_reports_dead(monkeypatch):
    sender = _FakeSender({"tok-live": True, "tok-dead": False})
    monkeypatch.setattr(push_module, "get_fcm_sender", lambda: sender)
    sup = _client(["tok-live", "tok-dead"])
    monkeypatch.setattr(push_module, "get_supabase_client", lambda: sup)

    push_to_member(WORKSPACE_ID, MEMBER_ID, title="Hi")

    # A delete against device_tokens happened (for the dead token).
    assert sup.table_calls.count("device_tokens") >= 2


def test_a_member_with_no_devices_is_a_clean_no_op(monkeypatch):
    sender = _FakeSender({})
    monkeypatch.setattr(push_module, "get_fcm_sender", lambda: sender)
    monkeypatch.setattr(push_module, "get_supabase_client", lambda: _client([]))

    push_to_member(WORKSPACE_ID, MEMBER_ID, title="Hi")

    assert sender.sent == []
