# `app/tests/conftest.py`

**What it does:** Defines pytest *fixtures*, which are reusable setup objects that tests receive as
arguments:
- `client`: a test client for an app with `CHAOS_MODE` **off** and build number `42`.
- `chaos_client`: the same, with `CHAOS_MODE` **on**.

**Why:** The Flask test client calls the endpoints in memory, with no real server or network
needed, so the tests are fast and run anywhere (your laptop or Jenkins).
