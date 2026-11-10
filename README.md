# DevSecOps Shield

**A secure, self-healing CI/CD pipeline on AWS with Blue-Green deployment**, built around
**SplitEase**, a small Flask bill-splitting app.

A `git push` to `main` runs unit tests, a secret scan (Gitleaks) and an image vulnerability scan
(Trivy). Only an image that passes every gate is pushed to Amazon ECR and deployed, by Ansible,
to the **idle** colour (blue or green) behind an Application Load Balancer. Once it's verified
healthy and running the new build, the ALB switches production traffic to it in one step. The old
colour keeps running, so a rollback takes seconds. Docker restart policies, ALB health checks and
Auto Scaling Groups heal failures without anyone stepping in. CloudWatch and a local Grafana
dashboard show what is happening, and alarms send email.

```
Build -> Test -> Secure -> Containerize -> Scan -> Store -> Deploy -> Verify -> Switch Traffic -> Self-Heal -> Monitor
```

- **Architecture diagrams:** [docs/architecture/architecture.md](docs/architecture/architecture.md)
- **Project report:** [docs/report/report.md](docs/report/report.md)
- **Study notes (one per file):** [docs/notes/](docs/notes/README.md)
- **Demo evidence checklist:** [docs/screenshots/CHECKLIST.md](docs/screenshots/CHECKLIST.md)
- **Build log / where things stand:** [PROGRESS.md](PROGRESS.md) · **Specification:** [CLAUDE.md](CLAUDE.md)

## Tech stack

| Area | Tool (version) | Role |
|---|---|---|
| App | Python 3.14, Flask 3.1, Gunicorn 27 | SplitEase: stateless, non-root container on port 5000 |
| Tests | pytest 9 | 144 unit tests (money maths in paise, API, chaos endpoints off by default) |
| CI/CD | Jenkins 2.580.2 LTS (Docker, local) | Multibranch pipeline, polls GitHub every minute |
| Security gate 1 | Gitleaks 8.30.1 | Secrets in the git history of the branch |
| Security gate 2 | Trivy 0.76.1 | HIGH/CRITICAL CVEs with a fix ⇒ fail ([policy](security/trivy-policy.md)) |
| Registry | Amazon ECR | Immutable `build-<N>` tags, keep last 5 |
| IaC | Terraform 1.16, AWS provider 6.72 | All AWS resources, local state |
| Config / deploy | Ansible core 2.21 + `amazon.aws` (aws_ec2 inventory) | Deploys to running instances |
| Runtime | EC2 t3.micro (Amazon Linux 2023), ALB, Auto Scaling | Blue + green environments, 1–2 instances each |
| State | SSM Parameter Store | `live_color`, per-colour `image_tag`, `chaos_mode` |
| Monitoring | CloudWatch (logs, metrics, alarms) + SNS email; Grafana 13.2.5 (Docker, local) | Dashboard "SplitEase - Production" with release annotations |

## Repository layout

```
app/                Flask app, templates, static files, pytest tests
Dockerfile          production image (slim, non-root, Gunicorn); .dockerignore = allow-list
Jenkinsfile         CI + Blue-Green release;  Jenkinsfile.rollback = rollback job
jenkins/            Jenkins image (pinned, checksum-verified tools), compose stack (Jenkins + Grafana), jobs as code
grafana/            Grafana provisioning (CloudWatch data source) + dashboard JSON
terraform/          all AWS infrastructure; terraform-runner-policy.json for your Terraform IAM user
ansible/            dynamic inventory, configure.yml, deploy.yml, docker role
scripts/            bluegreen.sh (switch/health helpers), grafana-annotate.sh
security/           trivy-policy.md
docs/               architecture, report, study notes, screenshots checklist
```

## Quick start

> Prerequisites: WSL2 Ubuntu (on Windows), Docker Desktop, Git, Python 3, AWS CLI v2, Terraform,
> Ansible, an AWS account (region ap-south-1) and an IAM user for Terraform (never root).

### 1. Run the app and tests locally (no AWS needed)
```bash
python3 -m venv .venv && .venv/bin/pip install -r app/requirements-dev.txt
cd app && ../.venv/bin/pytest -q          # 144 passed
../.venv/bin/python app.py                # http://localhost:5000
```
Docker: `docker build -t splitease:dev . && docker run -p 5000:5000 -e CHAOS_MODE=true --restart unless-stopped splitease:dev`

### 2. Start Jenkins and Grafana
```bash
cd jenkins
cp .env.example .env        # fill in: Grafana admin password + read-only AWS key (step 4)
docker compose up -d --build
```
- Jenkins: http://localhost:8080 (unlock with `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`).
  The jobs `splitease` (multibranch) and `splitease-rollback` are created from `jenkins/jobs/`.
- Grafana: http://localhost:3000 (user `admin`). The CloudWatch data source and dashboard are provisioned.

### 3. Create the AWS infrastructure
1. Attach [`terraform/terraform-runner-policy.json`](terraform/terraform-runner-policy.json) to
   the IAM user Terraform runs as (IAM console → Policies → Create → JSON).
2. `ssh-keygen -t ed25519 -f ~/.ssh/splitease-deploy -N ""` (Ansible's SSH key).
3. ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars   # my_ip = "<your IP>/32", alert_email = "..."
   terraform init && terraform plan -out=tfplan && terraform apply tfplan
   ```
   Then confirm the SNS subscription email.

### 4. Credentials (create them yourself; never commit them)
| Where | What |
|---|---|
| Jenkins → Credentials, *Secret text* `aws-access-key-id`, `aws-secret-access-key` | `aws iam create-access-key --user-name splitease-jenkins` |
| Jenkins → Credentials, *SSH Username with private key* `ec2-ssh-key` | user `ec2-user`, key from `clip.exe < ~/.ssh/splitease-deploy` |
| `jenkins/.env` | `aws iam create-access-key --user-name splitease-grafana` (read-only) |
| Jenkins → Credentials, *Secret text* `grafana-api-token` | Grafana → Administration → Service accounts → *Editor* → Add token |

### 5. Release
Push to `main`. Jenkins builds, scans, pushes `build-<N>` to ECR, deploys it to the idle colour,
verifies it and switches traffic. The live URL is the `app_url` Terraform output. Run
**`splitease-rollback`** to switch back.

### 6. Clean up (every session)
```bash
cd terraform && terraform destroy
```
Running cost is about **$0.08/hour** (mostly the ALB, 2–4 t3.micro instances and public IPv4
addresses). After `destroy` it is zero. The next `apply` recreates everything, but the IAM users
are new, so create fresh access keys.

## How a release works
1. **CI (every branch):** pytest → Gitleaks (full branch history, secrets redacted) → `docker build --pull`
   → Trivy. Any failure stops the pipeline, and nothing is pushed.
2. **Release (`main` only):** push `build-<N>` to ECR → idle colour = the opposite of
   `/splitease/live_color` → write the tag to SSM (for future instances) → Ansible updates the
   running instances → **health gate**: every idle target healthy 5 checks in a row (60 s, longer
   than the ALB's 45 s detection) **and** `:8080/version` returns build N → switch listeners (80 → new,
   8080 → old) → Grafana annotation.
3. **If anything fails before the switch:** port 80 is never touched and the idle colour's SSM tag is
   restored.

## Security controls
- Two pipeline gates (Gitleaks, Trivy) plus unit tests; only approved images reach ECR (immutable tags).
- Least-privilege IAM: instance role, Jenkins user, read-only Grafana user, scoped Terraform runner
  policy. **No access keys in git or Terraform state** (keys are created by hand and stored only in
  Jenkins Credentials / `.env`).
- Network: app port reachable only from the ALB; SSH and the test listener only from your IP;
  outbound HTTPS only; IMDSv2 with hop limit 1; encrypted EBS; ALB drops invalid headers.
- Container: slim base, `apt-get upgrade`, pip removed, non-root user, chaos endpoints 404 unless
  `CHAOS_MODE=true`.
- Supply chain: pinned tool versions with SHA-256 checks in the Jenkins image; pinned Python
  dependencies, provider lock file and Grafana version.

## Self-healing
Measured on AWS on 2026-11-10. The "terminate in the console" demo uses the same replacement
mechanism; its boot time is the one measured for the other replacements.

| Failure | Detection | Recovery | Measured |
|---|---|---|---|
| App crash (`/crash`) | container exits | Docker `--restart unless-stopped` | one 502 for ~2 s |
| Container stopped (`docker stop`) | ALB `/health` fails | ASG replaces the instance | unhealthy after 47 s, replaced at 1 min 47 s |
| CPU spike (`/cpu`) | ASG average CPU > 50% | target tracking adds an instance | scale-out ~4 min after the load started |
| Instance terminated | ASG below desired | ASG launches a replacement | new instance healthy in ~5–8 min |
| Bad release | idle health check (`ResponseCodeMismatch`) | no switch, SSM tag restored | stopped after ~90 s, live untouched |
| Problem after release | you / alarm | `splitease-rollback` job | seconds (no rebuild) |

## Monitoring
- **CloudWatch:** container logs (`/splitease/app`, stream per instance), 1-minute EC2 metrics,
  alarms (CPU > 70% per ASG, unhealthy hosts > 0 per target group) → SNS email.
- **Grafana** (http://localhost:3000 → *SplitEase → SplitEase - Production*): CPU and instances per
  ASG, healthy/unhealthy hosts, requests per colour (you can watch the Blue-Green switch), response
  time, 5xx, app logs, plus a yellow marker for each release and rollback. Refresh: 1 minute.

## Lessons learned (details in the report)
`AccessDenied` on the first apply (Terraform user had read-only rights) · EC2 rejects apostrophes in
security-group descriptions · zero-credit t3 instances need ~440 s to boot, so the grace period is
600 s · duplicate Jenkins triggers would release twice · a pasted SSH key with CRLF breaks OpenSSH ·
a single "healthy" poll can come from the *old* container (a bad release could slip through) ·
Grafana's code-mode CloudWatch queries need the builder fields.

## Future work
HTTPS (ACM), WAF, private subnets with VPC endpoints, Secrets Manager, remote Terraform state with
locking, IAM permissions boundary, drift detection, SonarQube/Semgrep/OWASP dependency scanning,
canary releases, containers on ECS/Kubernetes, multi-region.
