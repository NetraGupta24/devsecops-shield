# `grafana/provisioning/dashboards/splitease.yml`

**What it does:** A *dashboard provider*. It tells Grafana to load every dashboard JSON file from
`/var/lib/grafana/dashboards`, which is the repo's `grafana/dashboards` folder, mounted read-only by
docker compose. Dashboards appear in the folder **SplitEase**.

- `allowUiUpdates: false` + `disableDeletion: true`: the dashboard is code. Changes are made in the
  JSON file in git, reviewed and committed, not clicked together in the UI and lost.
- `updateIntervalSeconds: 30`: Grafana picks up a changed JSON file within 30 seconds.
