# `jenkins/docker-compose.yml`

**What it does:** Starts Jenkins with one command: `cd jenkins && docker compose up -d --build`.

**Line by line:**
- `build: .` builds `jenkins/Dockerfile`, tagged `splitease-jenkins:2.580.2`.
- `ports: "127.0.0.1:8080:8080"` makes Jenkins reachable at http://localhost:8080, from this laptop
  only and not from your Wi-Fi network.
- `volumes: jenkins_home:/var/jenkins_home` is a named Docker volume holding all Jenkins data (jobs,
  build history, credentials, Trivy's database). It survives `docker compose down`.
- `/var/run/docker.sock:/var/run/docker.sock` gives Jenkins' Docker CLI access to Docker Desktop's
  engine ("Docker-outside-of-Docker"). Images built by Jenkins show up in your normal `docker images`.
- `group_add: 1001` adds the `jenkins` user to the group that owns the Docker socket, so Jenkins
  can use Docker without running as root.
- `restart: unless-stopped` restarts Jenkins after Docker Desktop restarts.

**Security trade-off (viva question):** access to the Docker socket is effectively root access to
the Docker host. That is acceptable for a single-user learning setup on a laptop, but in a company
you would use separate build agents instead.

**Why Jenkins runs locally, not on EC2:** a free-tier t3.micro (1 GB RAM) can't run Jenkins plus
Docker builds plus Trivy, and running locally saves AWS credits. The catch is that GitHub can't
reach `localhost`, so Jenkins *polls* GitHub instead of receiving webhooks.

## Phase 14: the `grafana` service
- `grafana/grafana:13.2.5`, pinned (released 2026-10-27; upgraded deliberately).
- `127.0.0.1:3000:3000`: reachable only from this laptop: http://localhost:3000
- `env_file: .env (required)`: the admin password and the read-only AWS key come from the
  **gitignored** `jenkins/.env` (template: `.env.example`). Only Grafana gets these variables.
- Hardening: no self sign-up, no anonymous access, no phone-home analytics.
- Volumes: `grafana_data` (Grafana's database: users, tokens, annotations) and the repo's
  `grafana/provisioning` + `grafana/dashboards` folders, mounted **read-only** (configuration as code).
- Same compose network as Jenkins, so the pipeline reaches it at `http://grafana:3000`.
- Nothing new runs on EC2. Grafana *reads* CloudWatch over the AWS API. That's why no Prometheus or
  agents were needed.
