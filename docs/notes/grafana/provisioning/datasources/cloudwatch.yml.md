# `grafana/provisioning/datasources/cloudwatch.yml`

**What it does:** Creates Grafana's **CloudWatch data source** automatically when Grafana starts
("provisioning", i.e. configuration as code). Without it you would click through Grafana's UI to
add the data source, and the setup wouldn't be reproducible.

**Key lines:**
- `uid: cloudwatch`: a fixed ID, so the dashboard JSON can refer to this data source.
- `authType: keys` + `secureJsonData`: Grafana logs in to AWS with an access key. The values are
  **not** in the file. `${GRAFANA_AWS_ACCESS_KEY_ID}` is replaced at start-up with an environment
  variable that docker compose loads from the **gitignored** `jenkins/.env`.
- `defaultRegion: ap-south-1`.
- `editable: false`: the data source can only change through git.

**Which AWS identity?** The read-only IAM user `splitease-grafana` (see `terraform/iam.tf`). It can
read metrics and query the `/splitease/app` logs, and nothing else. Even if the laptop's Grafana
were compromised, nobody could change or delete anything in AWS with that key.
