# `jenkins/.env.example`

**What it is:** A template for `jenkins/.env`, the file that holds Grafana's secrets:
- `GF_SECURITY_ADMIN_PASSWORD`: password of Grafana's `admin` user.
- `GRAFANA_AWS_ACCESS_KEY_ID` / `GRAFANA_AWS_SECRET_ACCESS_KEY`: the read-only `splitease-grafana`
  IAM user's key.

**Why two files:** `.env.example` (empty values) is committed, so everyone knows which settings
exist. The real `.env` is **gitignored** (`.gitignore` contains `.env`), so the secrets never reach
GitHub, and Gitleaks would block them if they ever did. docker compose loads `.env` into the
Grafana container only; Jenkins never sees these values.
