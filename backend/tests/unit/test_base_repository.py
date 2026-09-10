from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from app.core.exceptions import NotFoundError
from app.repositories.base import BaseRepository


class _WidgetRepository(BaseRepository):
    table_name = "widgets"


def _client_returning(data):
    client = MagicMock()
    response = MagicMock(data=data)
    # Every builder method (select/eq/insert/update/range/maybe_single)
    # returns the same mock so arbitrary chains resolve to `response`.
    client.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = response
    client.table.return_value.select.return_value.range.return_value.execute.return_value = response
    client.table.return_value.insert.return_value.execute.return_value = response
    client.table.return_value.update.return_value.eq.return_value.execute.return_value = response
    return client, response


def test_get_by_id_returns_the_row():
    widget_id = uuid4()
    client, _ = _client_returning({"id": str(widget_id), "name": "Widget"})
    repo = _WidgetRepository(client)

    result = repo.get_by_id(widget_id)

    assert result["name"] == "Widget"
    client.table.assert_called_with("widgets")


def test_get_by_id_raises_not_found_when_row_is_missing():
    client, _ = _client_returning(None)
    repo = _WidgetRepository(client)

    with pytest.raises(NotFoundError):
        repo.get_by_id(uuid4())


def test_list_returns_rows():
    client, _ = _client_returning([{"id": "1"}, {"id": "2"}])
    repo = _WidgetRepository(client)

    result = repo.list()

    assert len(result) == 2


def test_insert_returns_the_created_row():
    client, _ = _client_returning([{"id": "1", "name": "New Widget"}])
    repo = _WidgetRepository(client)

    result = repo.insert({"name": "New Widget"})

    assert result["name"] == "New Widget"


def test_update_raises_not_found_when_rls_filters_out_the_row():
    client, _ = _client_returning([])
    repo = _WidgetRepository(client)

    with pytest.raises(NotFoundError):
        repo.update(uuid4(), {"name": "Renamed"})
