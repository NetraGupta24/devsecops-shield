# Demo evidence checklist (CLAUDE.md Section 11)

Save files here (`docs/screenshots/`) as `demoNN-short-name.png` / `.mp4`.

> **Capture all AWS console evidence BEFORE `terraform destroy`.** ASG activity history, target
> groups, ALB listeners, SSM parameters, ECR images, CloudWatch Logs and alarm history are deleted
> with the infrastructure. Jenkins history (localhost:8080) and the alert emails stay.

Live URL: `http://splitease-alb-1199863380.ap-south-1.elb.amazonaws.com/` (port 80), test port 8080
(your IP only). The URL changes after every destroy/apply.

## What already happened on 2026-11-10 (evidence you can screenshot now)

| # | Demo | Where the evidence is | Capture |
|---|---|---|---|
| 1 | Successful pipeline (v1 → v2) | Jenkins → `splitease` → `main` → builds **#8** (v1 → blue) and **#10** (v2 → green) | Stage View (all green); console tail `RELEASED: build-10 is live on green`; browser footer `SplitEase v2.0.0 · build N` |
| 2 | Failed unit test | `splitease` → `demo/failing-test` → build #1 | Stage View (red **Unit tests**, later stages skipped); *Test Result* page (31 failures) |
| 3 | Fake secret | `demo/fake-secret` → build #1 | Red **Gitleaks** stage; console: `RuleID: generic-api-key`, `File: app/payment_config.py`, `Secret: REDACTED`, `leaks found: 1` |
| 4 | Vulnerable image | `demo/vulnerable-image` → build #1 | Red **Trivy** stage; console table `gunicorn 21.2.0 … CVE-2024-1135 / CVE-2024-6827 HIGH`; ECR console showing only `build-<N>` tags from `main` |
| 5 | Bad release | `main` → build **#11** | Red **Health check (idle colour)**; console: `Target.ResponseCodeMismatch: bad release` and `Live colour blue was NOT touched`; ASG `splitease-green` → Activity: 18:24 "ELB system health check failure" + replacement |
| 6 | Rollback | `splitease-rollback` → build #1 | Stage View; console `port 80 now forwards to blue`, `Port 80 serves build 8` |
| 7 | `/crash` | CloudWatch Logs → `/splitease/app` → stream `blue/i-00502e5f8a36451b4` | Lines `CHAOS: /crash called` → `Shutting down: Master` → `Starting gunicorn` (18:53) |
| 8 | `docker stop` | ASG `splitease-green` → Activity | 19:00:49 "taken out of service in response to an ELB system health check failure" + "launched … unhealthy instance needing to be replaced" |
| 9 | `/cpu` scale-out (and scale-in) | ASG `splitease-blue` → Activity + Monitoring; CloudWatch metric `CPUUtilization` (ASG) | ~18:58 launch "in response to … TargetTracking … AlarmHigh"; CPU graph at 100%; later a scale-in activity (≈15 min after CPU dropped) |
| 10 | Terminate in console | *Not done yet, do it yourself (see below)* | |
| 11 | Alarm email | Your inbox + CloudWatch → Alarms → History | Emails "ALARM: splitease-blue-high-cpu" (18:58) and "ALARM: splitease-green-unhealthy-hosts" (18:26, 19:04) + their OK emails |

Also worth one screenshot each (they illustrate the architecture):
- ALB → Listeners: **80 → live target group**, **8080 → idle target group**
- Target groups `splitease-blue` / `splitease-green` → Targets (health status)
- SSM Parameter Store: `/splitease/live_color`, `/splitease/<colour>/image_tag`, `/splitease/chaos_mode`
- ECR `splitease`: tags `build-N`, *Tag immutability: Immutable*
- Jenkins dashboard with all 6 branches (green/red balls)

## How to re-run each demo on camera

| # | Steps |
|---|---|
| 1 | Make a small commit on `main` (or push the waiting local commits) and `git push`. Record Jenkins Stage View, then refresh the live page: the footer build number changes when traffic switches |
| 2–4 | Already recorded by Jenkins. To re-run, push an empty commit to the demo branch: `git switch demo/fake-secret && git commit --allow-empty -m "re-run demo" && git push`, then `git switch main` |
| 5 | `git merge demo/bad-release && git push` → record the red health-check stage and the live page staying unchanged → `git revert -m 1 HEAD && git push` |
| 6 | Jenkins → `splitease-rollback` → **Build Now**; refresh the live page before/after |
| 7 | Needs `chaos_mode=true` on the live colour (it is on now). Open `http://<alb>/crash` in the browser. SSH in and run `docker inspect -f '{{.RestartCount}}' splitease` before/after, and `docker ps` ("Up N seconds") |
| 8 | SSH into an instance: `sudo docker stop splitease`. Record the target turning *unhealthy* → *draining*, and the ASG Activity tab. Replacement healthy in ~8 min |
| 9 | Check the live instance has **≥ 10 CPU credits** (EC2 → instance → Monitoring → *CPU credit balance*). A fresh t3 has 0 and can't go above 10% CPU. Then open `http://<alb>/cpu?seconds=300` and record the ASG Monitoring/Activity tabs (scale-out after ~3–4 min) |
| 10 | EC2 console → select one `splitease-*` instance (the idle colour, so users aren't affected) → *Instance state* → **Terminate**. Record ASG Activity: a replacement is launched immediately and becomes healthy in ~8 min |
| 11 | Shows up in your inbox during demos 5, 8, 9 and 10 |
