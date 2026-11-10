# `app/app.py`

**What it does:** The Flask web application (SplitEase).

| Endpoint | Purpose |
|---|---|
| `GET /` | The web page (HTML from `templates/index.html`) |
| `POST /api/split` | JSON API: `{"total": "100", "people": ["A","B","C"]}` returns each person's share |
| `GET /health` | `{"status": "ok"}`. The **ALB health check** calls this every 15 s |
| `GET /version` | Version + build number. The **pipeline** checks this to prove the new build is running |
| `GET /crash` | Chaos mode only. Shuts down Gunicorn so the container exits and **Docker restarts it** |
| `GET /cpu?seconds=N` | Chaos mode only. Burns CPU in background processes so **Auto Scaling adds a server** |

**Key ideas to explain in the viva:**
- **`create_app()` factory:** tests can build an app with different settings (chaos on or off)
  without changing environment variables.
- **Stateless:** nothing is saved on the server, so servers can be replaced at any time (Auto
  Scaling, Blue-Green).
- **`CHAOS_MODE`:** the chaos endpoints return 404 unless `CHAOS_MODE=true`. Leaving "crash the
  server" endpoints open in production would itself be a security hole (anyone could take the site
  down).
- **Why `/crash` signals the parent process:** Gunicorn runs a *master* process plus *worker*
  processes. Our code runs in a worker. If only the worker died, the master would quietly start a
  new one and nothing visible would happen. So the worker sends `SIGINT` to the master, the whole
  server stops, the container exits, and Docker's `--restart unless-stopped` policy brings it back.
  That is self-healing level 1.
- **Why `/cpu` uses background processes:** Gunicorn kills any worker that takes more than 30 s to
  answer a request. So the endpoint starts one busy-loop process per CPU core, answers immediately
  (HTTP 202 Accepted), and the processes stop by themselves after N seconds (max 300).
- **Security headers** (`X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`)
  tell the browser to block common attacks like clickjacking and injected scripts.
- **`BUILD_NUMBER`** comes from an environment variable baked into the Docker image by Jenkins.

**How it connects:** Runs under Gunicorn inside the Docker image. The ALB calls `/health`, and the
Jenkins health-check stage calls `/version` on the test listener (port 8080).

## v2 additions (branch `feature/v2`)
- `APP_VERSION = "2.0.0"`.
- `POST /api/split` accepts `"mode": "equal" | "percentage" | "amount"`. Equal is still the default,
  so v1 API clients keep working (backwards compatible). For custom modes, `people` is
  `[{"name": "Asha", "value": "60"}, ...]`.
- `_calculate()` picks the right function from `splitter.py`.
- `GET /` passes `version` and `build` to the template, so the **footer shows "SplitEase v2.0.0 ·
  build 17"**. During the Blue-Green demo you can watch it change from v1 to v2 (and back on rollback).
