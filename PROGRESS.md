# PROGRESS

Resume a new session with: **"Continue from PROGRESS.md"**.
Mode for this build: Rule 2 is overridden (build end to end without stopping between phases).
All other CLAUDE.md rules still apply (Rule 7 secrets, Rule 8 cost approvals).
Last updated: 2026-11-10 (after real Jenkins CI runs).

## Status

| Step | Status | Notes |
|---|---|---|
| Phase 0 Setup | Done | All tools present. AWS CLI = IAM user `vle8-terraform-user`, ap-south-1. GitHub: git@github.com:NetraGupta24/devsecops-shield.git (public), SSH auth works |
| Phase 1 SplitEase v1 + pytest | Done | 87 tests pass, localhost:5000 works |
| Phase 2 Docker | Done | non-root uid 10001, Gunicorn; `/crash` + `--restart unless-stopped` verified |
| Phase 3 Jenkins local | Done (real run) | Push to GitHub was detected by the 1-minute branch scan, and all 6 branches built automatically (2026-11-10) |
| Phase 4 Security gates | Done (real run) | Jenkins: demo/failing-test failed at Unit tests, demo/fake-secret at Gitleaks (generic-api-key), demo/vulnerable-image at Trivy (2 HIGH); feature/v2 + demo/bad-release passed CI; main passed CI and stopped at Release (no AWS creds yet) |
| Phases 5–11 code | Written and validated | terraform fmt/validate/plan (placeholder vars: 45 to add, 0 errors), bash -n (incl. rendered user data), ansible syntax-check, live inventory query, mocked wait-healthy tests |
| v2 + demo branches | Done (local) | `feature/v2`, `demo/failing-test`, `demo/fake-secret`, `demo/vulnerable-image`, `demo/bad-release`, each verified locally. See docs/notes/demo-branches.md |
| Part B AWS | Demos 1, 5, 6 done; **chaos release in progress** (chaos_mode=true → live blue) | #10 v2 → green. Rollback job #1: green → blue (v1) OK. #11 bad release v2.1 → green: Ansible OK, ALB went stale-healthy 2 polls then ResponseCodeMismatch → stopped, tag restored, live blue untouched; ASG replaced the bad green instance (healthy again after ~8 min); green-unhealthy-hosts alarm fired (email). #12 revert → v2 live on green. CPU credits before the chaos release: blue 14.2 (old instance), green 2.3 |

## Key design decisions (and why)
- **Initial live colour = green** (Terraform), so the first release lands on **blue**. After the
  first switch, the old colour's SSM tag is seeded with the same build so it becomes healthy and can
  be rolled back to.
- **Multibranch job**: every branch runs CI; **only `main`** pushes to ECR and deploys. The bad
  release demo is done by merging `demo/bad-release` into main, then reverting.
- **Gitleaks** scans `--log-opts=HEAD` (full history of the built branch only), so the fake secret
  on its demo branch never breaks `main`.
- **Only one build trigger** (multibranch branch indexing every minute). `pollSCM` in the
  Jenkinsfile caused duplicate builds of the same commit, which on main would release twice and flip
  traffic again. The stale trigger was cleared from the main branch job (backup:
  `config.xml.bak-before-trigger-fix`).
- **Health gate**: `wait-healthy` requires 5 consecutive healthy polls (60 s > ALB's 45 s
  detection), and fails fast on `Target.ResponseCodeMismatch`. A mocked test proved a single
  "healthy" poll could pass a bad release.
- **Ansible rc 4** (unreachable host, usually an instance being replaced by the ASG) is tolerated;
  the ALB health check is the gate.
- **t3 standard credits = no launch credits**: measured user data = 311 s for the Docker install alone
  (72% CPU steal), ~440 s to healthy, so the ASG grace period is **600 s** (300 s caused endless
  replacements), and
  the `/cpu` scale-out demo must use an instance that has been up for 45+ minutes (otherwise CPU is
  capped at the 10% baseline).
- **Jenkins IAM access key is NOT created by Terraform** (it would end up in state). The student
  creates it after each apply and stores it only in Jenkins Credentials.
- App SG egress is HTTPS only; IMDSv2 with hop limit 1; detailed monitoring on (1-minute metrics).

## Environment facts
- Windows + WSL2 Ubuntu 26.04, Docker Desktop 29.8, docker.sock GID 1001, Python 3.14,
  Terraform 1.16 (AWS provider 6.72.0), Ansible core 2.20 on the laptop / 2.21.6 in Jenkins.
- `sudo` needs a password (the student runs any apt installs).
- Public IP at time of writing: 106.219.183.153 (home IPs can change; update `my_ip` and re-apply).

## Waiting on the student (credential steps Claude must not do)
1-4. DONE (GitHub SSH, deploy key, alert email in terraform.tfvars, Jenkins unlocked).
5. Approve `terraform apply` (plan summary given in chat).
6. After apply: create an access key for IAM user `splitease-jenkins` and add Jenkins credentials
   `aws-access-key-id`, `aws-secret-access-key` (Secret text) and `ec2-ssh-key` (SSH username
   `ec2-user` + private key `~/.ssh/splitease-deploy`); confirm the SNS subscription email.

## Next steps (Part B runbook)
1. DONE: job URLs set, all branches pushed, Jenkins restarted, CI verified on all 6 branches.
2. DONE: real `terraform plan` = 45 to add (saved as terraform/tfplan). WAITING for the student's
   explicit approval before `terraform apply`.
3. `terraform apply tfplan` (after approval).
4. Student adds Jenkins credentials and confirms the SNS email.
5. ~~v1 to blue (#8)~~ ~~v2 to green (#10)~~ ~~rollback~~ ~~bad release (#11) + revert (#12)~~.
   Planned demo order (keeps an old, credit-rich instance for /cpu): rollback (live → blue v1) →
   bad release (merge demo/bad-release → deploy to green fails, no switch) → `git revert` → release
   (live → green v2) → chaos_mode=true + release (live → blue, old instance) → /crash →
   /cpu (scale-out + CPU alarm email) → docker stop (ASG replaces) → terminate in console →
   chaos_mode=false.
   NOTE: every push to main starts a release, so commit locally and push only when a release is wanted.
6. Bad release demo (merge + revert). Self-healing demos (crash, docker stop, cpu, terminate). Alarm email.
7. List screenshots/recordings per demo. Ask before `terraform destroy`.
