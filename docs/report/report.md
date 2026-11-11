# DevSecOps Shield: A Secure, Self-Healing CI/CD Pipeline on AWS with Blue-Green Deployment

*Project report. Every result was measured on the real system on 2026-11-10 and 2026-11-11 unless
it is marked otherwise. Items that were not built are listed under Future Work. Diagrams and the
full configuration reference are in [`docs/architecture/architecture.md`](../architecture/architecture.md).*

## Abstract
DevSecOps Shield is a complete, automated delivery pipeline for a small web application,
SplitEase. Every code change is unit-tested, scanned for leaked secrets (Gitleaks) and for
vulnerable components (Trivy) before it may be packaged, stored and deployed. Deployment uses the
Blue-Green technique on AWS. The new version is installed on an idle copy of production, checked
through the real load balancer, and only then receives user traffic through a single switch that
can be reversed in seconds. The 47 AWS resources are defined as code with Terraform, configured with
Ansible and EC2 user data, and designed to heal themselves at the process, instance and capacity
level. Monitoring combines CloudWatch logs, metrics and email alarms with a Grafana dashboard on
which every release and rollback is marked automatically. In testing, a normal release took about
**3 minutes** from `git push` to live traffic. All three insecure test changes were blocked at the
correct gate. Two broken releases were stopped **without users noticing**, and every self-healing
scenario recovered without human action. Running the environment costs about **$0.08 per hour**, and
it is destroyed after each session.

## 1. Introduction
### 1.1 Problem
Manual deployments are slow and error-prone. A missed test, a password committed to the code or
an outdated library can reach production, and a bad release usually means downtime while someone
rebuilds the previous version. Servers fail too: processes crash, machines are lost, and traffic
spikes overload them.

### 1.2 Objectives
1. Automate build → test → security scanning → packaging → deployment for every change.
2. Block insecure changes automatically: leaked secrets and known-vulnerable components.
3. Release without downtime and roll back instantly (Blue-Green).
4. Recover from common failures without human action (self-healing).
5. Make the system observable: logs, metrics, alarms, dashboard.
6. Stay within a free-plan AWS credit budget.

### 1.3 Scope
One stateless Flask application, one AWS region (ap-south-1, Mumbai). Jenkins and Grafana run on
the developer's laptop in Docker. HTTPS, private networking, multi-region and container
orchestration are out of scope (Section 11).

## 2. Background and technologies
| Concern | Tool (version) | What it is, and why this project uses it |
|---|---|---|
| Version control | Git + GitHub | Stores every change. Branches separate features and the failure demonstrations |
| CI/CD orchestration | Jenkins 2.580.2 LTS | Runs the pipeline defined in the `Jenkinsfile`. *Multibranch*: every branch is built. Runs locally because a t3.micro (1 GB RAM) can't host it and local is free |
| Unit testing | pytest 9.2 | Fast automated tests; the JUnit report is shown in Jenkins |
| Secret scanning | Gitleaks 8.30.1 | Searches **every commit** of the branch for credentials. A secret deleted later is still leaked |
| Containers | Docker | Packages the app and its runtime into one image that runs the same everywhere |
| Vulnerability scanning | Trivy 0.76.1 | Lists known CVEs in the image's OS and Python packages and enforces the policy in `security/trivy-policy.md` |
| Registry | Amazon ECR | Private image storage with IAM control and immutable tags |
| Infrastructure as Code | Terraform 1.16 (AWS provider 6.72) | Describes all AWS resources in files: reviewable `plan`, repeatable `apply`/`destroy` |
| Configuration / deployment | Ansible core 2.21 + `amazon.aws` | Agentless (SSH), idempotent; a dynamic inventory finds the current servers via the EC2 API |
| Compute and traffic | EC2, Application Load Balancer, Auto Scaling | Health checks, instant listener switching, automatic replacement and scaling |
| Shared state | SSM Parameter Store | Free key-value store: which colour is live, which image each colour runs |
| Monitoring | CloudWatch + SNS; Grafana 13.2.5 | Native AWS logs, metrics, alarms and email; Grafana for one annotated dashboard |

## 3. Requirements
**Functional:** split bills exactly (equal, percentage, amount); health and version endpoints;
chaos endpoints for demonstrations only; build every branch; release only `main`; deploy to the
idle colour; verify before switching; one-click rollback; replace failed instances; scale on CPU;
email alarms; dashboard with release markers.

**Non-functional:** no secrets in git, state or logs; least-privilege IAM; app reachable only
through the load balancer; zero-downtime releases; reproducible environment (everything as code,
pinned versions); cost within free-plan credits (destroy after each session); beginner-friendly
documentation (one study note per file).

## 4. System design
### 4.1 Application (SplitEase)
- Endpoints `/`, `POST /api/split`, `/health`, `/version`; chaos endpoints `/crash`, `/cpu`.
- **Money in integer paise.** Equal split uses `divmod`, and leftover paise go one each to the
  first people. Percentage split uses integer basis points and the *largest remainder method*.
  Amount split requires the amounts to add up exactly. Shares **always add up to the exact total**.
- **Stateless**, so any instance can be replaced at any time.
- **Chaos endpoints** exist only when `CHAOS_MODE=true` (404 otherwise, and tested). `/crash` sends
  SIGINT to the Gunicorn **master**: killing only a worker would just make Gunicorn start another.
  `/cpu` starts one busy process per core and returns immediately, because Gunicorn kills requests
  that take longer than 30 s.
- Security headers (CSP, X-Frame-Options, nosniff, no-referrer); input limits; `textContent` in the UI.
- Image: `python:3.14.10-slim-trixie`, `apt-get upgrade`, pip removed, non-root uid 10001,
  Gunicorn with 2 workers on port 5000.

### 4.2 Pipeline
CI on every branch: checkout → pytest → Gitleaks → `docker build --pull` → Trivy. Release on
`main` only: push to ECR → find the idle colour → record the tag in SSM and deploy with Ansible
(after an SSH-key pre-flight check) → health gate → version gate → switch → Grafana annotation. A
separate rollback job swaps the listeners back. There is exactly one trigger (multibranch branch
indexing every minute) and one executor, so releases never overlap.

### 4.3 Infrastructure (47 Terraform resources)
- **Network:** one VPC with two public subnets in two Availability Zones and no NAT Gateway
  (~$30/month saved).
- **Security groups:** app traffic only from the ALB; SSH and the test listener only from the
  developer's IP; HTTPS-only egress.
- **Load balancing:** two target groups (blue, green) and two listeners (80 production, 8080 test).
- **Compute:** two launch templates (t3.micro, standard CPU credits, IMDSv2, encrypted gp3,
  detailed monitoring) and two Auto Scaling Groups (min 1 / max 2, ELB health check, 600 s grace,
  target tracking 50% CPU).
- **Also:** four SSM parameters, ECR (immutable, keep 5), CloudWatch log group, four alarms, SNS
  topic with email, and least-privilege IAM (EC2 role, Jenkins user, read-only Grafana user; no
  access keys in state).

### 4.4 Blue-Green deployment
`/splitease/live_color` names the live colour; the other is idle. A release goes to the idle colour
and must pass **two gates** before the switch:
(a) every idle target healthy for **5 consecutive checks (60 s)**;
(b) the test listener returns the **new build number** 5 times in a row.
The switch is two `ModifyListener` calls plus an SSM update. Because the previous colour keeps
running, rollback is the same switch in reverse. Initially green is marked live and empty, so the
first release goes to blue, and green is then given the same build as a rollback target.

### 4.5 Self-healing
| Layer | Mechanism |
|---|---|
| Process | Docker `--restart unless-stopped` |
| Instance | ALB health check + ASG (ELB health check) → replacement booted by user data into the version stored in SSM |
| Capacity | Target tracking on 50% average CPU (1-minute metrics) |
| Release | Health and version gates; the idle tag is restored on failure; the ASG heals the idle colour |

### 4.6 Monitoring
- **CloudWatch:** container logs via the Docker `awslogs` driver; 1-minute EC2 metrics and ASG group
  metrics; four alarms (CPU > 70% per ASG, unhealthy hosts > 0 per target group) → SNS email.
- **Grafana:** runs locally in Docker and reads CloudWatch through a read-only IAM user. The data
  source and the "SplitEase - Production" dashboard are provisioned from git.
  - The dashboard shows CPU and instances per ASG, healthy and unhealthy hosts, requests per colour,
    response time, 5xx and app logs, refreshing every minute.
  - The load-balancer panels use CloudWatch `SEARCH` expressions, so they survive destroy/apply.
  - Jenkins posts an annotation at every switch and rollback, through a script that always exits 0
    inside `catchError`, so monitoring can never fail a release.

### 4.7 Security design (DevSecOps)
| Threat | Control |
|---|---|
| Credentials leaked in code | Gitleaks gate over the full branch history; `.gitignore`; keys only in Jenkins Credentials / gitignored `.env`; Terraform never creates access keys |
| Vulnerable dependencies | Trivy gate (fixable HIGH/CRITICAL), pinned dependencies, `--pull`, `apt-get upgrade` |
| Over-privileged automation | Four separate least-privilege identities. Jenkins may only switch *our two* listeners; Grafana is read-only; the Terraform runner is limited to ap-south-1 and `splitease-*` |
| Network exposure | App port only from the ALB; SSH and 8080 only from one IP; HTTPS-only egress; Jenkins and Grafana on 127.0.0.1 |
| Credential theft from containers | IMDSv2 required, hop limit 1 |
| Supply chain of the tooling | Pinned versions with SHA-256 checks (Trivy itself was hit by a supply-chain attack in 2026) |
| Abuse of chaos endpoints | Disabled unless `CHAOS_MODE=true`; unit-tested |

## 5. Implementation
| Phase | Built | Verified by |
|---|---|---|
| 0 Setup | WSL2 Ubuntu 26.04, Docker Desktop, Python, AWS CLI, Terraform, Ansible, GitHub repo | Tool versions; `aws sts get-caller-identity` as an IAM user |
| 1 App + tests | SplitEase v1, 87 tests | pytest; localhost:5000 |
| 2 Docker | Slim non-root image, Gunicorn, `.dockerignore` allow-list | `/crash` + restart policy locally (restart count 0 → 1) |
| 3 Jenkins | Custom image (pinned, SHA-256), compose, jobs as code, polling | Pushing branches started builds automatically |
| 4 Security gates | Gitleaks + Trivy, `trivy-policy.md` | Fake-secret and vulnerable-image branches failed |
| 5–7 AWS base | Terraform: ECR, IAM, VPC, SGs, SSM, launch templates, ASGs, ALB | Plan/apply; app reachable on the ALB |
| 8 Ansible | Dynamic inventory, `deploy.yml`, deploy stage | Release #10 updated green in place |
| 9 Blue-Green | Green, gates, switch, rollback job | v1 → v2 switch (#10) and rollback (#1) |
| 10 Self-healing | Scaling policy, chaos endpoints in AWS | `/crash`, `docker stop`, `/cpu` (Section 6.5) |
| 11 Monitoring | Log group, alarms, SNS email | Logs in CloudWatch; alarm state changes |
| 12 Recording | Evidence checklist | *Screenshots/recordings by the student (in progress)* |
| 13 Documentation | README, architecture, this report, 52 study notes | Diagrams match the implementation |
| 14 Grafana | Local Grafana, read-only IAM user, dashboard as code, annotations | Release #15 annotation + `/cpu` on the dashboard |

Repository: 35+ commits on `main`, branches `feature/v2` and four `demo/*` branches; about 3,300
lines of application, test, pipeline, script, Terraform, Ansible and dashboard code.

## 6. Testing and results
### 6.1 Unit tests (144)
| File | Tests | Covers |
|---|---|---|
| `test_splitter.py` | 120 | Paise conversion and validation; equal split exactness; the "shares add up" property for 6 totals × 6 group sizes and 6 totals × 6 percentage mixes; largest remainder; ties; amount split |
| `test_app.py` | 24 | Every endpoint, API errors (non-JSON, bad values, unknown mode), security headers, v2 footer, chaos endpoints 404 when off, `/crash` and `/cpu` behaviour with mocks |

### 6.2 Security gates (real Jenkins runs)
| Branch | Build #1 and #2 result | Evidence |
|---|---|---|
| `demo/failing-test` | **FAILED at Unit tests** | 31 failed / 113 passed; later stages skipped |
| `demo/fake-secret` | **FAILED at Gitleaks** | `generic-api-key` in `app/payment_config.py`, value redacted; Docker build skipped |
| `demo/vulnerable-image` | **FAILED at Trivy** | gunicorn 21.2.0: CVE-2024-1135, CVE-2024-6827 (HIGH); never pushed |
| `feature/v2`, `demo/bad-release` | Passed CI | Release stages skipped (not `main`) |

Trivy also found real problems in our own first image: two HIGH `zlib1g` CVEs (fixed with
`apt-get upgrade`) and five HIGH CVEs in libraries bundled inside pip (fixed by removing pip). The
final image has **0** HIGH/CRITICAL findings.

### 6.3 Releases (`main`)
| Build | Change | Result | Duration |
|---|---|---|---|
| #7 | v1, first attempt | Failed at Push to ECR: malformed AWS key credential (fixed) | 34 s |
| #8 | v1 → blue | **Live.** Ansible couldn't load the SSH key, but the ASG replacement booted the new version via user data | 724 s |
| #9 | v2 → green | **Blocked by the version gate:** green healthy but still on the old build; live untouched | 242 s |
| #10 | v2 → green | **Live** (Ansible updated green in place) | 186 s |
| Rollback #1 | green → blue | v1 live again, no rebuild | 154 s |
| #11 | v2.1 *bad release* → green | **Blocked by the health gate** (`ResponseCodeMismatch`); live untouched | 137 s |
| #12 | revert → green | **Live** | 193 s |
| #13 | chaos-enabled release → blue | **Live** | 191 s |
| #14 | Phase 14 code → green | **Live.** Grafana token didn't exist yet: "annotation skipped", build still SUCCESS | 194 s |
| #15 | release → blue | **Live.** "Grafana annotation added: Release build-15: traffic green -> blue" | 282 s |

A normal release takes **about 3 minutes** from push to live traffic.

### 6.4 Demonstrations (CLAUDE.md §11)
| # | Demo | Status | Evidence |
|---|---|---|---|
| 1 | Successful pipeline v1 → v2 | Done | #8, #10 (and #12–#15) |
| 2 | Failed unit test | Done | `demo/failing-test` #1, #2 |
| 3 | Fake secret | Done | `demo/fake-secret` #1, #2 |
| 4 | Vulnerable image | Done | `demo/vulnerable-image` #1, #2 |
| 5 | Bad release | Done | #11 |
| 6 | Rollback | Done | `splitease-rollback` #1 |
| 7 | `/crash` | Done | 2026-11-10 18:53 UTC |
| 8 | `docker stop` | Done | 2026-11-10 18:59–19:01 UTC (green) |
| 9 | `/cpu` scale-out + scale-in | Done | 2026-11-10 18:58 out / 19:15 in; again 2026-11-11 17:43 out |
| 10 | Terminate in console | **To be recorded by the student** | Same mechanism as the replacements in demos 5 and 8 |
| 11 | Alarm email | Done (state changes and SNS sends recorded) | Inbox screenshots by the student |

### 6.5 Self-healing measurements
| Scenario | Observation |
|---|---|
| `/crash` | One HTTP 502 for ~2 s; Docker restart count 0 → 1; CloudWatch Logs show `CHAOS: /crash called` → `Shutting down: Master` → `Starting gunicorn` within 2 s |
| `docker stop` | Docker didn't restart it (manual stop); ALB unhealthy after 47 s; ASG replaced the instance 1 min 47 s after the stop |
| Bad release (idle colour) | ASG replaced the failing instance ~1.5 min after it turned unhealthy; replacement healthy ~8 min later on the restored version |
| `/cpu` (run 1) | ASG CPU 100%; scale-out to 2 at 18:58 (~4 min); second instance healthy at 19:06; scale-in at 19:15 (~16 min after the load ended) |
| `/cpu` (run 2, Grafana) | 17:39:23 start → 51% → 100%; scale-out at 17:43:17 (~4 min) |
| Instance boot | Zero-credit t3.micro: Docker install alone 311 s at 72% CPU steal; healthy after ~5–8 min |

### 6.6 Alarms (CloudWatch → SNS email)
| Time (UTC) | Alarm | Change | Cause |
|---|---|---|---|
| 11-10 18:26 → 18:35 | green unhealthy-hosts | ALARM → OK | Bad release, then self-heal |
| 11-10 18:58 → 19:01 | blue high-cpu | ALARM → OK | `/cpu` run 1 |
| 11-10 19:02 | blue unhealthy-hosts | ALARM | Scale-out instance still booting (expected side effect) |
| 11-10 19:04 | green unhealthy-hosts | ALARM | `docker stop` |
| 11-11 17:43 → 17:45 | blue high-cpu | ALARM → OK | `/cpu` run 2 |

### 6.7 Grafana (Phase 14)
- **Tested before commit** with a throwaway Grafana against the real account. The data source health
  check passed for metrics and logs, and every panel returned data. This found the Grafana 13 quirk
  in Section 7.
- **Annotation script** tested for a valid token, no token, a wrong token (HTTP 401) and Grafana
  unreachable (HTTP 000). It always exited 0.
- **In production:** release #14 (no token) logged "annotation skipped" and still succeeded. Release
  #15 logged "annotation added". `/cpu` run 2 put blue's CPU at 100% and its instance count to 2 on
  the dashboard.

## 7. Problems encountered and how they were solved
| # | Problem | Root cause | Fix |
|---|---|---|---|
| 1 | Trivy failed our first image | Base image older than Debian fixes; pip's vendored libraries | `apt-get upgrade`; remove pip after installing |
| 2 | Gitleaks flagged a line of the Ansible inventory | Generic API-key rule: the word "key" followed by a dotted, random-looking value | Bracket form `ec2_tags['Env']` (same meaning); commit amended before pushing |
| 3 | A single "healthy" poll could approve a bad release | The ALB shows the **old** container's state for up to 45 s | 5 consecutive healthy polls; fail fast on `ResponseCodeMismatch`. Found with a mocked test, then seen for real in #11 (2 stale "healthy" polls) |
| 4 | First apply: AccessDenied everywhere | Terraform user had only read permissions | Scoped `terraform-runner-policy.json`, validated with Access Analyzer + policy simulation |
| 5 | `InvalidParameterValue` on security groups | Apostrophe not allowed in descriptions (not caught by `plan`) | Reworded; Terraform created only the missing 22 resources |
| 6 | New instances replaced before they could become healthy | t3 standard mode has no launch credits; boot ~440 s | Grace period 300 → 600 s (measured) |
| 7 | Two builds for one commit | `pollSCM` + multibranch indexing | One trigger; stale trigger cleared from the job |
| 8 | `IncompleteSignature` from AWS | Key ID and secret pasted into one credential | One fresh key, printed one value per line |
| 9 | `Load key: error in libcrypto` in Ansible | SSH key pasted into the browser was corrupted | Key normalised in the pipeline; pre-flight check; re-entered with `clip.exe` |
| 10 | Rollback waited 60 s instead of 2 checks | `bluegreen.sh` dropped its third argument | Argument passed through |
| 11 | Revert not pushed | `grep -c` returned "no match" = failure and stopped an `&&` chain | Pushed separately; lesson about shell exit codes |
| 12 | Grafana SEARCH panels failed | Grafana 13 needs the builder fields even in code mode | Added empty builder fields; every panel re-tested |
| 13 | Gitleaks flagged this report | It quoted the false positive of problem 2 word for word | Rephrased |
| 14 | Jenkins couldn't reach the servers the next day | Home IP changed overnight | `my_ip` updated; apply changed only the 2 IP rules |
| 15 | **Grafana admin password shown in a local transcript** | BusyBox `wget` rejected `--password=…` and echoed it | Reported to the student immediately; logged in PROGRESS.md; verification switched to logs and Jenkins output. The student chose not to rotate (Grafana is only on 127.0.0.1) |

## 8. Security assessment
**Achieved:** no real secret in git history (Gitleaks clean on `main`); no access key in Terraform
state; four least-privilege identities; app reachable only through the ALB; container credentials
protected by IMDSv2; image with 0 fixable HIGH/CRITICAL CVEs; insecure changes stopped by the gates.

**Residual risks:**
- HTTP only (no TLS).
- Instances in public subnets (protected by security groups).
- The Terraform runner can still create IAM roles/users named `splitease-*` (a permissions boundary
  is future work).
- Jenkins has access to the Docker socket (root-equivalent on the laptop's Docker).
- Grafana and Jenkins depend on the laptop.
- The Grafana admin password was exposed once in a local transcript, and the student accepted the risk.

## 9. Cost
| Item | Approx. per hour (Mumbai, on demand) |
|---|---|
| Application Load Balancer | $0.023 |
| 2 × t3.micro (up to 4 while scaling) | $0.022 |
| 4 public IPv4 addresses | $0.020 |
| EBS gp3 + detailed monitoring | ~$0.01 |
| SSM, IAM, SNS email, alarms, ECR, logs | cents |
| **Total** | **≈ $0.08/hour** |

The environment ran from about 13:45 UTC on 2026-11-10 to the evening of 2026-11-11 (not destroyed
overnight), roughly 28 hours, which is about **$2.3** of the $131 free-plan credits (estimate).
Without the destroy rule it would cost about $55 a month.

## 10. Limitations
- **Free-plan instances:** zero-credit t3 instances boot slowly (~5–8 min), and the `/cpu` demo needs
  an instance that has built up CPU credits.
- **Single developer:** local Terraform state, and Jenkins and Grafana run on one laptop.
- **Manual key handling:** IAM access keys must be created again after every destroy/apply.
- **Changing home IP:** `my_ip` has to be updated whenever the home IP changes.

## 11. Future work
HTTPS with ACM; WAF; private subnets with VPC endpoints; Secrets Manager; remote Terraform state
with locking; IAM permissions boundary; drift detection; SonarQube/Semgrep/OWASP dependency
scanning; canary releases; ECS/Kubernetes; multi-region. Prometheus was deliberately not used,
because Grafana reads CloudWatch directly.

## 12. Conclusion
The project meets all six objectives:
- Insecure or broken changes were stopped automatically at the correct gate.
- Good releases reached users in about three minutes with no downtime, and both broken releases were
  stopped before users saw them.
- Failures at the process, instance and capacity level were repaired without human action, and
  every release is visible on the dashboard.
- The whole environment can be rebuilt from git with one `terraform apply` and removed to zero cost
  with one `terraform destroy`.

---

## Appendix A: Glossary
| Term | Meaning in this project |
|---|---|
| CI/CD | Continuous Integration (build + test every change) / Continuous Delivery (release automatically) |
| DevSecOps | Security checks built *into* the pipeline instead of done at the end |
| Infrastructure as Code | Cloud resources described in files (Terraform) instead of console clicks |
| Blue-Green | Two identical environments; one live, one idle; a release goes to idle, then traffic switches |
| ALB / listener / target group | Load balancer / port it listens on (80, 8080) / group of instances it forwards to |
| Health check | ALB calling `/health` every 15 s to decide if an instance may receive traffic |
| Auto Scaling Group | Keeps 1–2 healthy instances; replaces failed ones; scales on CPU |
| Target tracking | Scaling policy that keeps a metric (average CPU) near a target (50%) |
| User data | Script an EC2 instance runs at its first boot |
| SSM Parameter Store | AWS key-value store, here the "memory" of what runs where |
| IAM / least privilege | AWS identities and permissions / give each identity only what it needs |
| IMDSv2 | Instance metadata service with session tokens; hop limit 1 keeps containers out |
| CVE | Public ID of a known vulnerability (e.g. CVE-2024-1135) |
| Idempotent | Running it twice changes nothing the second time (Ansible) |
| Dynamic inventory | Ansible asks AWS which servers exist instead of using a fixed list |
| CPU credits (t3) | Burst budget of a t3 instance; *standard* mode caps CPU at 10% when it runs out |
| Annotation | Vertical marker on a Grafana graph, here "release" or "rollback" |
| Multibranch pipeline | Jenkins job that builds every branch that has a Jenkinsfile |

## Appendix B: Command cheat sheet
```bash
# local
cd app && ../.venv/bin/pytest -q
cd jenkins && docker compose up -d
# AWS session
cd terraform && terraform plan -out=tfplan && terraform apply tfplan
./scripts/bluegreen.sh status
aws ssm put-parameter --name /splitease/chaos_mode --value true --type String --overwrite
curl http://<alb>/version ; curl http://<alb>:8080/version
cd terraform && terraform destroy
```

## Appendix C: Likely viva questions
1. **Why Blue-Green rather than updating servers in place?** Users never see a half-updated system,
   the new version is tested through the real load balancer first, and rollback is a switch, not a
   rebuild.
2. **What exactly must pass before traffic switches?** Every idle target healthy for 5 consecutive
   checks, *and* port 8080 returning the new build number 5 times in a row.
3. **Why 5 consecutive checks?** The ALB keeps reporting the old container's status for up to 45 s
   (3 × 15 s). One "healthy" reading could belong to the old container. Build #11 showed exactly
   this.
4. **Why both Ansible and user data?** Ansible updates servers that are already running. User data
   sets up servers that Auto Scaling creates later. Both read the same SSM tag.
5. **What happens if a release fails?** Port 80 is never touched; the idle colour's SSM tag is
   restored, and the ASG heals the idle colour.
6. **How does Gitleaks catch a secret that was deleted later?** It scans every commit in the
   branch's history, not just the current files.
7. **Why `--ignore-unfixed` in Trivy?** Failing on vulnerabilities that have no fix would block every
   release, including security releases. They're re-checked on every build.
8. **How are credentials protected?** They're never in git or Terraform state. They live in Jenkins
   Credentials and a gitignored `.env`, each identity has least privilege, and Gitleaks blocks
   commits containing secrets.
9. **Why does `/crash` signal the Gunicorn master?** Killing a worker is invisible, because Gunicorn
   restarts it. Stopping the master stops the container, which shows Docker's restart policy at work.
10. **Why is the grace period 600 s?** It was measured: a zero-credit t3.micro took 311 s just to
    install Docker. With 300 s, instances were killed before they could become healthy.
11. **Why run Jenkins locally?** A free-plan t3.micro (1 GB RAM) can't run Jenkins, Docker builds
    and Trivy. Running locally is free. GitHub can't reach localhost, so Jenkins polls.
12. **How can monitoring never break a release?** The annotation script always exits 0 and is
    wrapped in `catchError`. Build #14 proved it with the token missing.
13. **What's the difference between `/crash` and `docker stop` recovery?** `/crash` is fixed by
    Docker on the same instance in ~2 s. A stopped container isn't restarted by Docker, so the ALB
    health check and the ASG replace the whole instance.
14. **How much does it cost and how do you control it?** About $0.08/hour. Everything is destroyed
    after each session, the ASG is capped at 2 instances, ECR keeps 5 images, logs 7 days, and
    there's no NAT Gateway.

## Appendix D: References
Jenkins Pipeline and Multibranch documentation · Gitleaks · Trivy · Terraform AWS provider · Ansible
`amazon.aws` collection (aws_ec2 inventory) · AWS documentation: Application Load Balancer (health
checks, listeners), EC2 Auto Scaling (health checks, target tracking), burstable performance
instances (CPU credits, standard mode), CloudWatch (alarms, Logs Insights, SEARCH expressions), SSM
Parameter Store, IMDSv2 · Grafana CloudWatch data source and provisioning documentation.
