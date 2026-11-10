# `terraform/cloudwatch.tf`

**What it does:** Monitoring.
- **Log group `/splitease/app`** (kept 7 days): the Docker `awslogs` log driver sends every
  container's output here, one log stream per instance (`<colour>/<instance-id>`).
- **SNS topic `splitease-alerts`** + **email subscription**: alarms publish to the topic, and SNS
  emails you. You must click the confirmation link AWS sends first.
- **Alarms, per colour:**
  - **High CPU:** ASG average CPU > 70% for 3 minutes.
  - **Unhealthy hosts:** `UnHealthyHostCount > 0` for 2 minutes, meaning an instance is failing
    `/health`.
  - Both also notify when they return to OK.
