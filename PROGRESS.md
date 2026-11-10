# PROGRESS

Resume a new session with: **"Continue from PROGRESS.md"**.
Mode for this build: Rule 2 is overridden (build end to end without stopping between phases).
All other CLAUDE.md rules still apply (Rule 7 secrets, Rule 8 cost approvals).
Last updated: 2026-11-10.

## Status

| Step | Status | Notes |
|---|---|---|
| Phase 0 Setup | Done, except GitHub | All tools present. AWS CLI = IAM user `vle8-terraform-user`, ap-south-1. **GitHub remote + auth not set up yet** |
| Phase 1 SplitEase v1 + pytest | Done | 87 tests pass, localhost:5000 works |
| Phase 2 Docker | Done | non-root uid 10001, Gunicorn; `/crash` + `--restart unless-stopped` verified |
| Phase 3 Jenkins local | Built and running; **real run waiting on GitHub** | `jenkins/` image (pinned, sha256-verified tools), compose, jobs as code. Container `jenkins` up on http://localhost:8080, waiting for the student to unlock |
| Phase 4 Security gates | Done (verified with the same commands inside the Jenkins image) | Gitleaks + Trivy; Dockerfile hardened (apt upgrade, pip removed) → 0 HIGH/CRITICAL |
| Phases 5–11 code | Written and validated | terraform fmt/validate/plan (placeholder vars: 45 to add, 0 errors), bash -n (incl. rendered user data), ansible syntax-check, live inventory query, mocked wait-healthy tests |
| v2 + demo branches | Done (local) | `feature/v2`, `demo/failing-test`, `demo/fake-secret`, `demo/vulnerable-image`, `demo/bad-release`, each verified locally. See docs/notes/demo-branches.md |
| Part B AWS | Not started | Needs: student approval of the plan/cost summary |

## Key design decisions (and why)
- **Initial live colour = green** (Terraform), so the first release lands on **blue**. After the
  first switch, the old colour's SSM tag is seeded with the same build so it becomes healthy and can
  be rolled back to.
- **Multibranch job**: every branch runs CI; **only `main`** pushes to ECR and deploys. The bad
  release demo is done by merging `demo/bad-release` into main, then reverting.
- **Gitleaks** scans `--log-opts=HEAD` (full history of the built branch only), so the fake secret
  on its demo branch never breaks `main`.
- **Health gate**: `wait-healthy` requires 5 consecutive healthy polls (60 s > ALB's 45 s
  detection), and fails fast on `Target.ResponseCodeMismatch`. A mocked test proved a single
  "healthy" poll could pass a bad release.
- **Ansible rc 4** (unreachable host, usually an instance being replaced by the ASG) is tolerated;
  the ALB health check is the gate.
- **t3 standard credits = no launch credits**, so the ASG grace period is 300 s (variable), and
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
1. GitHub repo URL (public or private) + Git auth from WSL (SSH key added to GitHub).
2. `ssh-keygen -t ed25519 -f ~/.ssh/splitease-deploy -N "" -C splitease-deploy` (EC2 deploy key).
3. Email address for CloudWatch alerts (goes in gitignored `terraform/terraform.tfvars`).
4. Unlock Jenkins at http://localhost:8080, install suggested plugins, create the admin user.
5. Approve `terraform apply` (plan summary given in chat).
6. After apply: create an access key for IAM user `splitease-jenkins` and add Jenkins credentials
   `aws-access-key-id`, `aws-secret-access-key` (Secret text) and `ec2-ssh-key` (SSH username
   `ec2-user` + private key `~/.ssh/splitease-deploy`); confirm the SNS subscription email.

## Next steps (Part B runbook)
1. Fill in the job URLs in `jenkins/jobs/*/config.xml`, push all branches, rebuild/restart Jenkins.
2. Verify CI on all branches (demo branches fail at the right stage; main fails at "Push to ECR"
   until AWS credentials exist).
3. `terraform plan` (real values) → `terraform apply` (after approval).
4. Student adds Jenkins credentials and confirms the SNS email.
5. Build main → v1 to blue → switch. Merge feature/v2 → v2 to green → switch. Rollback job.
6. Bad release demo (merge + revert). Self-healing demos (crash, docker stop, cpu, terminate). Alarm email.
7. List screenshots/recordings per demo. Ask before `terraform destroy`.
