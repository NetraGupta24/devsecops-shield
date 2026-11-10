# PROGRESS

Resume a new session with: **"Continue from PROGRESS.md"**.
Mode for this build: Rule 2 is overridden (build end to end without stopping between phases).
All other CLAUDE.md rules still apply (Rule 7 secrets, Rule 8 cost approvals).

## Status

| Phase | Status | Notes |
|---|---|---|
| 0 Setup | Done, except the GitHub remote | Tools present. AWS CLI works as IAM user `vle8-terraform-user`, region ap-south-1. GitHub not connected yet (no remote, no auth) |
| 1 SplitEase v1 + pytest | Done | 87 tests pass. App works on localhost:5000 |
| 2 Docker | Next | |
| 3 Jenkins local | Not started | |
| 4 Security gates | Not started | |
| 5-11 Code (Terraform, Ansible, Jenkinsfiles) | Not started | |
| v2 + demo branches | Not started | |
| Part B AWS deploy | Not started (needs approval) | |

## Environment facts
- Windows + WSL2 Ubuntu 26.04, Docker Desktop 29.8 (WSL integration), Python 3.14, Terraform 1.16,
  Ansible core 2.20 (apt), AWS CLI 2.31.
- `sudo` needs a password, so the student must run any `apt install` themselves.
- No GitHub SSH key or credential helper yet.

## Open problems / waiting on student
- GitHub repo URL and GitHub authentication from WSL.

## Next step
- Phase 2: Dockerfile, `.dockerignore`, build and run locally, `/crash` + restart policy test.
