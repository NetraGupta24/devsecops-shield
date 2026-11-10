"""Tests for the HTTP endpoints in app.py."""

import signal

import app as app_module


# ---- normal endpoints -------------------------------------------------------

def test_index_page(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"SplitEase" in response.data


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_version(client):
    response = client.get("/version")
    assert response.status_code == 200
    data = response.get_json()
    assert data["version"] == app_module.APP_VERSION
    assert data["build"] == "42"


def test_security_headers(client):
    response = client.get("/")
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert "default-src 'self'" in response.headers["Content-Security-Policy"]


# ---- the split API ----------------------------------------------------------

def test_api_split_equal(client):
    response = client.post("/api/split", json={"total": "100", "people": ["Asha", "Ben", "Chitra"]})
    assert response.status_code == 200
    data = response.get_json()
    assert data["total"] == "100.00"
    assert [s["amount"] for s in data["shares"]] == ["33.34", "33.33", "33.33"]
    assert sum(s["paise"] for s in data["shares"]) == data["total_paise"] == 10000


def test_api_split_accepts_json_number(client):
    response = client.post("/api/split", json={"total": 99.99, "people": ["A", "B"]})
    assert response.status_code == 200
    assert [s["paise"] for s in response.get_json()["shares"]] == [5000, 4999]


def test_api_split_rejects_non_json(client):
    response = client.post("/api/split", data="total=100", content_type="application/x-www-form-urlencoded")
    assert response.status_code == 400
    assert "error" in response.get_json()


def test_api_split_rejects_json_list(client):
    response = client.post("/api/split", json=["100", ["A"]])
    assert response.status_code == 400


def test_api_split_invalid_total(client):
    response = client.post("/api/split", json={"total": "-10", "people": ["A"]})
    assert response.status_code == 400
    assert "greater than zero" in response.get_json()["error"]


def test_api_split_missing_people(client):
    response = client.post("/api/split", json={"total": "10"})
    assert response.status_code == 400


def test_api_split_get_not_allowed(client):
    assert client.get("/api/split").status_code == 405


# ---- chaos endpoints are hidden unless CHAOS_MODE=true -----------------------

def test_crash_is_404_when_chaos_off(client):
    assert client.get("/crash").status_code == 404


def test_cpu_is_404_when_chaos_off(client):
    assert client.get("/cpu?seconds=5").status_code == 404


def test_crash_signals_process_when_chaos_on(chaos_client, monkeypatch):
    calls = []

    class FakeTimer:  # replaces threading.Timer so the test process is NOT really killed
        def __init__(self, delay, func, args):
            calls.append((func, args))

        def start(self):
            pass

    monkeypatch.setattr(app_module.threading, "Timer", FakeTimer)
    response = chaos_client.get("/crash")
    assert response.status_code == 202
    assert calls and calls[0][1][1] == signal.SIGINT


def test_cpu_starts_background_processes_and_caps_seconds(chaos_client, monkeypatch):
    started = []
    monkeypatch.setattr(app_module.subprocess, "Popen", lambda args, **kwargs: started.append(args))
    response = chaos_client.get("/cpu?seconds=9999")
    assert response.status_code == 202
    data = response.get_json()
    assert data["seconds"] == app_module.MAX_CPU_SECONDS
    assert len(started) == data["processes"] >= 1
    assert started[0][-1] == str(app_module.MAX_CPU_SECONDS)


def test_cpu_rejects_bad_seconds(chaos_client, monkeypatch):
    monkeypatch.setattr(app_module.subprocess, "Popen", lambda *a, **k: None)
    assert chaos_client.get("/cpu?seconds=abc").status_code == 400
    assert chaos_client.get("/cpu?seconds=0").status_code == 400


# ---- v2 -------------------------------------------------------------------

def test_footer_shows_version_and_build(client):
    page = client.get("/").get_data(as_text=True)
    assert f"v{app_module.APP_VERSION}" in page
    assert "build 42" in page


def test_api_split_percentage(client):
    response = client.post("/api/split", json={
        "total": "1000", "mode": "percentage",
        "people": [{"name": "Asha", "value": "50"}, {"name": "Ben", "value": "30"}, {"name": "Chitra", "value": "20"}],
    })
    assert response.status_code == 200
    data = response.get_json()
    assert data["mode"] == "percentage"
    assert [s["amount"] for s in data["shares"]] == ["500.00", "300.00", "200.00"]


def test_api_split_amount(client):
    response = client.post("/api/split", json={
        "total": "1000", "mode": "amount",
        "people": [{"name": "Asha", "value": "699.99"}, {"name": "Ben", "value": "300.01"}],
    })
    assert response.status_code == 200
    assert [s["paise"] for s in response.get_json()["shares"]] == [69999, 30001]


def test_api_split_amount_mismatch(client):
    response = client.post("/api/split", json={
        "total": "1000", "mode": "amount",
        "people": [{"name": "Asha", "value": "600"}, {"name": "Ben", "value": "300"}],
    })
    assert response.status_code == 400
    assert "add up to 900.00" in response.get_json()["error"]


def test_api_split_percentage_bad_value(client):
    response = client.post("/api/split", json={
        "total": "100", "mode": "percentage",
        "people": [{"name": "Asha", "value": "abc"}, {"name": "Ben", "value": "50"}],
    })
    assert response.status_code == 400
    assert "Asha's percentage" in response.get_json()["error"]


def test_api_split_custom_mode_needs_objects(client):
    response = client.post("/api/split", json={"total": "100", "mode": "amount", "people": ["Asha", "Ben"]})
    assert response.status_code == 400


def test_api_split_unknown_mode(client):
    response = client.post("/api/split", json={"total": "100", "mode": "random", "people": ["A"]})
    assert response.status_code == 400


def test_api_split_equal_still_default(client):
    response = client.post("/api/split", json={"total": "10", "people": ["A", "B", "C"]})
    assert response.get_json()["mode"] == "equal"
    assert [s["amount"] for s in response.get_json()["shares"]] == ["3.34", "3.33", "3.33"]
