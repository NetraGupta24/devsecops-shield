# `app/tests/test_app.py`

**What it tests:** The HTTP endpoints, as CLAUDE.md requires.
- `/health` returns 200 `{"status": "ok"}`, and `/version` returns the version and build number.
- `/api/split` happy path, plus invalid input returning 400 with an error message.
- **Chaos endpoints return 404 when `CHAOS_MODE` is off.** This is a security test.
- With chaos on, `/crash` and `/cpu` are tested with *mocks* (`monkeypatch`). The test replaces
  `threading.Timer` and `subprocess.Popen` with fakes, so the test run isn't actually killed and
  no CPU is burned.
