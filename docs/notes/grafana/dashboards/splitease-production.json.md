# `grafana/dashboards/splitease-production.json`

**What it is:** The **"SplitEase - Production"** dashboard as code (uid `splitease-production`,
refresh **1 minute**, last 1 hour).

| Panel | CloudWatch source | What to look for in the demos |
|---|---|---|
| CPU per ASG | `AWS/EC2 CPUUtilization` per `AutoScalingGroupName` (blue / green) | `/cpu`: the line jumps to ~100%; dashed lines mark 50% (scaling target) and 70% (alarm) |
| Instances per ASG | `AWS/AutoScaling GroupInServiceInstances` (solid) + `GroupDesiredCapacity` (dashed) | `/cpu`: desired 1 → 2, then in service 1 → 2; scale-in later |
| Healthy / unhealthy hosts | `AWS/ApplicationELB HealthyHostCount` / `UnHealthyHostCount` per target group | `docker stop`, bad release: unhealthy goes to 1, then the replacement turns healthy |
| ALB requests by colour | `RequestCount` per target group + total | **Blue-Green switch**: traffic moves from one colour's line to the other |
| Response time | `TargetResponseTime` average and p95 | Rises under `/cpu` load |
| 5xx errors | `HTTPCode_ELB_5XX_Count` (ALB) and `HTTPCode_Target_5XX_Count` (app) | `/crash`: a short ALB 5xx bar while the container restarts |
| App logs | CloudWatch Logs Insights on `/splitease/app` | `CHAOS: /crash called` → `Shutting down: Master` → `Starting gunicorn` |

**Annotations:** a yellow vertical marker for every Grafana annotation tagged `splitease`. Jenkins
posts one at every traffic switch ("Release build-N: blue -> green") and rollback.

**Design decision (viva):** the load-balancer panels use **CloudWatch SEARCH expressions** that
match "splitease" instead of fixed IDs. The ALB and target groups get new IDs on every
`terraform destroy`/`apply`, and SEARCH makes the dashboard keep working without edits.

**Lesson learned:** Grafana 13's CloudWatch plugin failed every code-mode SEARCH query with a
generic *"An error occurred within the plugin"* until the empty builder fields (`namespace`,
`metricName`, `dimensions`, `statistic`) were added to each query. This was found by testing every
panel through Grafana's query API against the real account before the dashboard was committed.
