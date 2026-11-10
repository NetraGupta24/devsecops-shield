"""Shared pytest fixtures: a test client with chaos mode off, and one with it on."""

import pytest

from app import create_app


@pytest.fixture
def client():
    app = create_app({"TESTING": True, "CHAOS_MODE": False, "BUILD_NUMBER": "42"})
    return app.test_client()


@pytest.fixture
def chaos_client():
    app = create_app({"TESTING": True, "CHAOS_MODE": True, "BUILD_NUMBER": "42"})
    return app.test_client()
