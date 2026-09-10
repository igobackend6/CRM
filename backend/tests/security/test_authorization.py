from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from app.core.exceptions import PermissionDeniedError
from app.security import authorization as authz
from app.security.permissions import Permission


def _client_with_rpc_result(value: bool):
    client = MagicMock()
    client.rpc.return_value.execute.return_value = MagicMock(data=value)
    return client


def test_has_permission_calls_the_database_rpc_by_name():
    client = _client_with_rpc_result(True)
    workspace_id = uuid4()

    result = authz.has_permission(client, workspace_id, Permission.LEADS_CREATE)

    assert result is True
    client.rpc.assert_called_once_with(
        "has_permission",
        {"p_workspace_id": str(workspace_id), "p_permission_code": "leads.create"},
    )


def test_require_permission_raises_when_the_database_says_no():
    client = _client_with_rpc_result(False)

    with pytest.raises(PermissionDeniedError):
        authz.require_permission(client, uuid4(), Permission.LEADS_DELETE)


def test_require_permission_passes_when_the_database_says_yes():
    client = _client_with_rpc_result(True)

    # Should not raise.
    authz.require_permission(client, uuid4(), Permission.LEADS_READ)


def test_require_workspace_member_calls_is_workspace_member_rpc():
    client = _client_with_rpc_result(True)
    workspace_id = uuid4()

    authz.require_workspace_member(client, workspace_id)

    client.rpc.assert_called_once_with("is_workspace_member", {"p_workspace_id": str(workspace_id)})


def test_require_workspace_member_raises_when_not_a_member():
    client = _client_with_rpc_result(False)

    with pytest.raises(PermissionDeniedError):
        authz.require_workspace_member(client, uuid4())
