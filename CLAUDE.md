# CLAUDE.md — DevSecOps Shield

This file is the project specification. Read it at the start of every session and keep all work consistent with it.

## 1. Project

**Title:** DevSecOps Shield: A Secure, Self-Healing CI/CD Pipeline on AWS with Blue-Green Deployment

**Summary:** A developer pushes code to GitHub. Jenkins runs unit tests, a Gitleaks secret scan, builds a Docker image and scans it with Trivy. Only an image that passes every gate is pushed to AWS ECR. Terraform provisions the AWS infrastructure. Ansible deploys the approved image to the idle (Blue or Green) environment behind an Application Load Balancer. After a health check passes, the ALB switches production traffic to the new version, and the old one stays available for rollback. Auto Scaling Groups, ALB health checks and Docker restart policies make the system self-healing. CloudWatch collects logs and metrics and sends alarm emails. A local Grafana dashboard visualises the CloudWatch data, with Jenkins annotations marking every traffic switch.

**Core principle:** Build → Test → Secure → Containerize → Scan → Store → Deploy → Verify → Switch Traffic → Self-Heal → Monitor

## 2. Rules for Claude (how to work with the student)

1. The student is a **complete beginner in DevOps**. Before introducing any tool, explain what it is, why this project needs it, and how it connects to the other tools.
2. **One phase at a time** (see Section 9). At the end of each phase: summarise what was built, list the files created, give the exact commands to verify it works, and **stop**. Do not start the next phase until the student confirms it works.
3. Explain every command before running it. Explain line by line when asked.
4. After each working phase, suggest a git commit with a clear message.
5. If something fails, troubleshoot the current step first. Do not change the architecture to get around an error. If a change really seems necessary, explain why and ask first.
6. Do not add tools that are not in this file (see Section 10).
7. **Secrets:** never ask for, print, echo, or write real credentials into any file, commit, or chat. The student sets AWS credentials themselves with `aws configure`. Jenkins gets credentials only through the Jenkins Credentials store. Use **fake** secrets only, and only for the Gitleaks demo.
8. **Cost-sensitive commands** (`terraform apply`, `terraform destroy`, any AWS `create`/`run`/`delete` command): always run `terraform plan` first, summarise in plain language what will be created/changed/destroyed and its cost impact, then wait for explicit approval.
9. Everything in the report and diagrams must match what is actually implemented. Anything planned but not built is labelled "Future work".
10. Before Phase 0, ask which operating system the laptop runs. On Windows, do everything inside **WSL2 (Ubuntu)**, because Ansible does not run natively on Windows.

## 3. Student's environment

- AWS account on the **Free plan** (credit-based; the account closes 6 months after creation or when credits run out, whichever comes first). Region: **ap-south-1 (Mumbai)**.
- EC2 instance types must be Free-plan eligible: use **t3.micro** (default); t3.small only if truly needed. Do not use t2.medium or anything larger.
- Claude Pro (Claude Code via Claude Desktop).
- Jenkins runs **locally on the laptop in Docker**, not on EC2 (a 1 GB instance cannot handle Docker builds plus Trivy, and running it locally saves credits).
- Grafana (Phase 14) also runs **locally in Docker**, in the same compose stack as Jenkins (`127.0.0.1:3000`). Nothing extra runs on EC2.

## 4. The application: SplitEase

A Flask bill/expense splitter. It is **stateless** (no database): Auto Scaling and Blue-Green replace servers constantly, so any data stored on a server would be lost.

| Endpoint | Purpose |
|---|---|
| `GET /` | Web page: enter a total amount and people's names, see each person's share |
| `POST /api/split` | JSON API for the split calculation |
| `GET /health` | Returns 200 `{"status": "ok"}`. Used by the ALB and the pipeline health check |
| `GET /version` | Returns app version + build number. The pipeline uses it to confirm the new environment runs the new build |
| `GET /crash` | **Only when `CHAOS_MODE=true`**, otherwise 404. Must stop the whole container, not just one Gunicorn worker (Gunicorn would silently respawn a worker), e.g. by signalling the Gunicorn master process |
| `GET /cpu?seconds=N` | **Only when `CHAOS_MODE=true`**, otherwise 404. Burns CPU for N seconds (cap at 300) in a background process and returns immediately (Gunicorn kills sync workers that block for more than 30 s) |

- **v1:** equal split. **v2:** adds custom split (by percentage or amount) and shows the version in the page footer, so the Blue-Green switch is visible on screen.
- Money is calculated in paise (integers). Rounding remainders are distributed so that shares always add up exactly to the total.
- Runs with Gunicorn on port **5000** inside the container, as a **non-root user**.
- Chaos endpoints are disabled by default. Leaving them always on would itself be a security hole, which is why `CHAOS_MODE` exists.
- **Unit tests (pytest):** split maths incl. rounding, invalid input, `/health`, `/version`, and chaos endpoints return 404 when `CHAOS_MODE` is off.

## 5. Who does what (keep these roles distinct)

| Component | Role |
|---|---|
| Git / GitHub | Version control / remote repository |
| Jenkins | CI/CD orchestration (runs locally in Docker; triggered by Poll SCM because GitHub cannot reach localhost) |
| pytest | Unit tests |
| Gitleaks | Secret scanning (Security Gate 1) |
| Docker | Containerisation |
| Trivy | Container vulnerability scanning (Security Gate 2) |
| ECR | Registry for approved images only |
| Terraform | Provisions all AWS infrastructure. Run by the student from the laptop, **not** from Jenkins |
| Ansible | Deploys approved images to running EC2 instances |
| EC2 user data | Bootstraps **new** instances created by Auto Scaling, so they run the correct version with nobody around |
| SSM Parameter Store | Stores the current image tag per colour, the live colour and the chaos-mode flag (standard parameters only) |
| ALB | Traffic distribution, health checks, Blue-Green switching |
| Auto Scaling Groups | Instance capacity and replacement of unhealthy instances |
| CloudWatch | Logs, metrics, alarms (email via SNS) |
| IAM | Least-privilege permissions |
| AWS CLI | Used by Jenkins for ECR login, SSM and ALB listener changes |
| Grafana | Local dashboard (Docker, pinned version) over CloudWatch metrics and logs, read through a read-only IAM user. Data source and dashboard are provisioned as code. Jenkins adds an annotation at every traffic switch and rollback |

## 6. Pipeline (Jenkinsfile)

1. **Checkout**
2. **Unit tests**: pytest; failure stops the pipeline.
3. **Gitleaks**: scan the repository including git history; any finding stops the pipeline.
4. **Docker build**: tag `splitease:build-<BUILD_NUMBER>` (never only `latest`).
5. **Trivy**: fail on HIGH and CRITICAL vulnerabilities that have a fix available (`--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`). Document the policy in `security/trivy-policy.md`.
6. **Push to ECR**: only reached if stages 2–5 pass.
7. **Find idle colour**: read `/splitease/live_color` from SSM; the target is the other colour.
8. **Deploy to idle colour**: update `/splitease/<colour>/image_tag` in SSM, then run Ansible against the idle colour's instances.
9. **Health check**: all targets in the idle colour's target group are healthy, **and** `/version` through the ALB **test listener (port 8080)** returns the new build number.
10. **Switch traffic**: point the port 80 listener at the idle colour's target group, point the 8080 test listener at the old colour, update `/splitease/live_color`.
11. **Post**: print the live URL and version. If any stage fails, the port 80 listener is never touched, so the current live colour stays live.

A separate **rollback job** (`Jenkinsfile.rollback`) swaps the listeners back and updates `/splitease/live_color`.

After every traffic switch (stage 10 and the rollback job), Jenkins posts a **Grafana annotation** (credential `grafana-api-token`). This step must never fail the pipeline.

## 7. AWS infrastructure (Terraform)

- **Network:** one VPC, **2 public subnets in 2 AZs** (the ALB needs two), Internet Gateway, route table. **No NAT Gateway and no private subnets** (cost).
- **Security groups:** ALB SG allows 80 from anywhere and 8080 from the student's IP only (`var.my_ip`). App SG allows 5000 from the ALB SG only and 22 from the student's IP only.
- **ECR:** repository `splitease`, immutable tags, lifecycle policy keeping the last 5 images, `force_delete = true` so `terraform destroy` works.
- **ALB:** listener 80 (production) and listener 8080 (test); target groups `blue` and `green` health-checking `/health`. Both listeners use `lifecycle { ignore_changes = [default_action] }`, because Jenkins switches them and Terraform must not switch them back.
- **Launch templates (blue, green):** Amazon Linux 2023, t3.micro, `credit_specification { cpu_credits = "standard" }` (t3 defaults to "unlimited", which can bill extra for sustained CPU), IAM instance profile, tags `Project=splitease` and `Env=<colour>`. User data installs Docker, logs in to ECR, reads the colour's image tag and chaos flag from SSM, and runs the container with `--restart unless-stopped` and the `awslogs` log driver.
- **Auto Scaling Groups (blue, green):** min 1 / desired 1 / max 2, `health_check_type = "ELB"`, grace period long enough for user data to finish (~180 s), target-tracking policy on average CPU 50%, `lifecycle { ignore_changes = [desired_capacity] }`.
- **SSM parameters (standard):** `/splitease/live_color`, `/splitease/blue/image_tag`, `/splitease/green/image_tag`, `/splitease/chaos_mode` (default `false`). Terraform creates them with `ignore_changes = [value]`, because the pipeline updates them.
- **IAM:**
  - EC2 instance role: ECR read-only, `ssm:GetParameter` on `/splitease/*`, CloudWatch Logs write.
  - Separate **Jenkins IAM user** (keys stored only in Jenkins Credentials): ECR push to `splitease`, SSM get/put on `/splitease/*`, `elasticloadbalancing:Describe*` + `ModifyListener`, `ec2:DescribeInstances`, `autoscaling:Describe*`.
  - Separate **Grafana IAM user** (read-only; key only in the gitignored `jenkins/.env`): CloudWatch `GetMetricData`/`ListMetrics`/`Describe*`, Logs Insights queries on `/splitease/*`, `ec2:Describe*` and `tag:GetResources` for name lookups.
  - Terraform runs as the student's own IAM user (never the root account).
- **CloudWatch:** log group `/splitease/app` (7-day retention); alarms for high CPU per ASG and `UnHealthyHostCount > 0` per target group, sending to an SNS topic with an email subscription (`var.alert_email`).
- **State:** local state in `terraform/`. `*.tfstate*`, `.terraform/` and `terraform.tfvars` are gitignored; commit `.terraform.lock.hcl` and a `terraform.tfvars.example`.

## 8. Self-healing behaviour

| Failure | Detection | Automatic recovery |
|---|---|---|
| App process crashes (`/crash`) | Container exits | Docker restart policy restarts the container |
| Container stays down (`docker stop`) | ALB health check on `/health` fails | ASG (ELB health check) terminates and replaces the instance; user data boots the correct version |
| CPU spike (`/cpu`) | ASG average CPU > 50% | Target tracking adds a second instance |
| Instance terminated | ASG below desired capacity | ASG launches a replacement |
| Bad release | Idle-colour health check fails in the pipeline | No traffic switch; live colour stays live |
| Problem found after release | Student / CloudWatch alarm | Rollback job swaps traffic back |

## 9. Phases (one at a time; verify before moving on)

| # | Phase | Done when |
|---|---|---|
| 0 | Setup: OS check (WSL2 on Windows), Git, Docker, Python, AWS CLI v2, Terraform, Ansible; GitHub repo `devsecops-shield`; `aws sts get-caller-identity` works with the student's own IAM user | Every tool prints its version; first commit is on GitHub |
| 1 | SplitEase v1 + pytest | App works on localhost:5000; tests pass |
| 2 | Docker: slim image, non-root, Gunicorn, `.dockerignore` | Container serves the app; `/crash` with `CHAOS_MODE=true` + restart policy restarts it locally |
| 3 | Jenkins locally: custom image (`jenkins/Dockerfile` with Docker CLI, Python, Gitleaks, Trivy, AWS CLI, Ansible + `amazon.aws` + boto3) via `docker compose`; pipeline Checkout → Tests → Docker Build; Poll SCM | A git push triggers a build automatically |
| 4 | Security gates: Gitleaks + Trivy stages, `security/trivy-policy.md` | Fake-secret branch and vulnerable-image branch both fail the pipeline |
| 5 | Terraform basics + ECR + Jenkins IAM user; Jenkins pushes to ECR | Image with build tag visible in ECR |
| 6 | Network, IAM instance role, SSM parameters, Blue launch template + ASG | Blue instance boots and runs the app via user data |
| 7 | ALB, target groups, 80 + 8080 listeners | App reachable on the ALB DNS name; target healthy |
| 8 | Ansible dynamic inventory (`aws_ec2` plugin) + `deploy.yml`; Jenkins deploy stage | A push deploys a new build to Blue automatically |
| 9 | Green environment + Blue-Green stages + rollback job | v1 → v2 switch and rollback both work |
| 10 | Scaling policy + self-healing demos (Section 8) | Every row of the self-healing table demonstrated |
| 11 | CloudWatch logs, alarms, SNS email | App logs visible; alarm email received |
| 12 | Full integration + record all demos (Section 11) | Screenshots and screen recordings saved in `docs/` |
| 13 | Documentation: human-facing `README.md`, architecture diagram, report | Diagram matches the real implementation |
| 14 | Grafana: local Docker (compose), CloudWatch data source via read-only IAM user, "SplitEase - Production" dashboard as code (CPU and instances per ASG, healthy/unhealthy hosts, ALB requests, response time, 5xx, app logs; refresh 1 min), Jenkins annotations on switch/rollback | A deployment shows its annotation and the `/cpu` demo is visible on the dashboard |

Phases 0–4 run entirely on the laptop and cost nothing on AWS.

## 10. Cost rules and things not to add

**Cost rules**
- `terraform destroy` at the end of every working session that used AWS; `terraform apply` again next time.
- The ALB is the most expensive piece (roughly $16/month if left running 24/7, paid from credits). Public IPv4 addresses are also billed hourly. Both disappear on destroy.
- No NAT Gateway, Elastic IPs, RDS or other databases, EKS/ECS, AWS Config.
- Keep ASGs at max 2, ECR lifecycle at 5 images, log retention at 7 days.
- Remind the student to check Billing → Credits and the Free Tier page regularly.

**Do not add** (list as Future work only, unless the student explicitly asks): Kubernetes/K3s/EKS/ECS/Helm, ArgoCD, Prometheus, SonarQube, Semgrep, OWASP dependency scanning, drift detection, HTTPS/ACM, WAF, Secrets Manager, multi-region, microservices, canary deployment.

## 11. Final demos

1. Successful pipeline: push v2 → all gates pass → Green deployed → health check → traffic switched → v2 live.
2. Failed unit test → pipeline stops, nothing deployed.
3. Fake secret committed → Gitleaks fails → nothing deployed. (GitHub push protection may block pushing a fake secret; if it does, use the option to mark it as a test secret, or use a fake secret pattern GitHub does not block.)
4. Vulnerable base image or dependency → Trivy fails → image never reaches ECR.
5. Bad release (`/health` returns 500) → idle health check fails → no switch, live version unaffected.
6. Rollback job → traffic back to the previous version.
7. `/crash` → container restarts by itself.
8. `docker stop` on an instance → ASG replaces the instance.
9. `/cpu` → second instance launches, later scales back in.
10. Terminate an instance in the console → ASG replaces it.
11. CloudWatch alarm email received.

## 12. Repository structure

```text
devsecops-shield/
├── CLAUDE.md
├── README.md                 # written in Phase 13
├── PROGRESS.md               # session-to-session progress log
├── app/
│   ├── app.py
│   ├── templates/
│   ├── requirements.txt
│   └── tests/
├── Dockerfile
├── .dockerignore
├── .gitignore
├── Jenkinsfile
├── Jenkinsfile.rollback
├── jenkins/
│   ├── Dockerfile
│   ├── docker-compose.yml    # Jenkins + Grafana
│   ├── .env.example          # template for the gitignored .env (Grafana secrets)
│   ├── plugins.txt  init.groovy.d/  jobs/
├── grafana/                  # Phase 14
│   ├── provisioning/datasources/cloudwatch.yml
│   ├── provisioning/dashboards/splitease.yml
│   └── dashboards/splitease-production.json
├── scripts/
│   ├── bluegreen.sh          # shared Blue-Green helper (pipeline + rollback)
│   └── grafana-annotate.sh   # never-failing Grafana annotation
├── terraform/
│   ├── provider.tf  variables.tf  outputs.tf
│   ├── network.tf  security_groups.tf  ecr.tf  iam.tf
│   ├── alb.tf  launch_templates.tf  autoscaling.tf
│   ├── ssm.tf  cloudwatch.tf
│   ├── user_data.sh.tftpl
│   ├── terraform-runner-policy.json   # IAM policy for the student's Terraform user
│   └── terraform.tfvars.example
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/aws_ec2.yml
│   ├── playbooks/deploy.yml
│   ├── playbooks/configure.yml
│   └── roles/docker/
├── security/
│   └── trivy-policy.md
└── docs/
    ├── architecture/
    ├── screenshots/
    ├── notes/                # one study note per file
    └── report/
```
