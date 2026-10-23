from unittest.mock import patch
import pytest
from django.db import OperationalError


@pytest.mark.django_db
def test_health_does_not_consume_auth_quota(client):
    for _ in range(105):
        response = client.get("/api/health/")
        assert response.status_code == 200
        assert not response.cookies
    assert client.get("/api/auth/csrf/").status_code == 200


def test_health_database_failure_is_sanitized(client):
    with patch("lab.api.health.connection.cursor", side_effect=OperationalError("private db details")):
        response = client.get("/api/health/")
    assert response.status_code == 503
    assert b"private" not in response.content
