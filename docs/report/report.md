# DevSecOps Shield: A Secure, Self-Healing CI/CD Pipeline on AWS with Blue-Green Deployment

*Project report (draft). Every result below was measured on the real system on 2026-11-10 unless
it is marked otherwise. Items that were not built are listed under Future Work.*

## Abstract
DevSecOps Shield is a complete delivery pipeline for a small web application, SplitEase. Every code
change is tested, scanned for leaked secrets and for vulnerable dependencies before it may be
packaged, stored and deployed. Deployment uses the Blue-Green technique on AWS. A new version is
installed on an idle copy of the production environment, verified, and only then receives user
traffic, through a single load-balancer switch that can be reversed in seconds. The infrastructure
is defined as code with Terraform, configured with Ansible, and designed to heal itself at three
levels: process, instance and capacity. Monitoring combines CloudWatch alarms with a Grafana
dashboard on which each release is marked. In testing, a normal release took about **3 minutes**
from `git push` to live traffic. A deliberately broken release was stopped **without users noticing**,
and every self-healing scenario recovered automatically.

## 1. Introduction
### 1.1 Problem
Manual deployments are slow and risky. A missed test, a committed password or an outdated library
can reach production, and a bad release usually means downtime while someone rebuilds the previous
version. Servers also fail: processes crash, instances die, and traffic spikes overload them.

### 1.2 Objectives
1. Automate build → test → security scanning → packaging → deployment for every change.
2. Block insecure changes automatically (secrets, known-vulnerable components).
3. Deploy without downtime, and roll back instantly (Blue-Green).
4. Recover from common failures without human action (self-healing).
5. Make the system observable (logs, metrics, alarms, dashboard).
6. Keep the whole AWS footprint within a free-plan credit budget.

### 1.3 Scope
A stateless Flask app, one AWS region (ap-south-1), Jenkins and Grafana on the developer's laptop
in Docker. HTTPS, multi-region and container orchestration are out of scope (Section 9).

## 2. Technologies and why each was chosen
| Concern | Tool | Reason |
|---|---|---|
| Version control | Git + GitHub | Branches for features and failure demonstrations |
| Orchestration | Jenkins (Docker, local) | Pipeline as code (`Jenkinsfile`), multibranch builds; local to save credits (a t3.micro has only 1 GB RAM) |
| Unit tests | pytest | Fast, readable tests; JUnit report shown in Jenkins |
| Secret scanning | Gitleaks | Scans the full git history of the branch: a secret deleted later is still a leak |
| Container | Docker | Same artefact from laptop to production |
| Image scanning | Trivy | OS and Python package CVEs, with a documented fail policy |
| Registry | Amazon ECR | Private, IAM-controlled, immutable tags |
| Infrastructure | Terraform | Declarative, reviewable plans, repeatable create/destroy |
| Deployment | Ansible | Agentless (SSH), idempotent, dynamic AWS inventory |
| Runtime | EC2 + ALB + Auto Scaling | Health checks, listener switching, automatic replacement and scaling |
| Shared state | SSM Parameter Store | Free, simple key-value store that new instances read at boot |
| Monitoring | CloudWatch + SNS, Grafana | Native AWS logs/metrics/alarms; Grafana for one combined, annotated view |

## 3. System design
The architecture diagrams are in [`docs/architecture/architecture.md`](../architecture/architecture.md).

### 3.1 Application (SplitEase)
- Endpoints: `/`, `POST /api/split`, `/health`, `/version`; v2 adds percentage and amount splits.
- **Money is stored in integer paise**, never floating point. Rounding leftovers go one paisa at a
  time to the first people (equal split) or to the largest cut-off fractions (percentage split, the
  largest remainder method), so the shares **always add up to the exact total**.
- **Stateless**, so instances can be replaced at any time.
- **Chaos endpoints** `/crash` and `/cpu` exist only when `CHAOS_MODE=true` (404 otherwise, which
  is tested). `/crash` signals the Gunicorn *master*, not just a worker, so the whole container
  stops. `/cpu` burns CPU in background processes, because Gunicorn kills requests longer than 30 s.
- Container: `python:3.14-slim`, `apt-get upgrade`, pip removed after install, non-root user, Gunicorn.

### 3.2 Pipeline
CI on every branch: checkout → pytest → Gitleaks → `docker build --pull` → Trivy. Release on `main`
only: push to ECR → find the idle colour → record the tag in SSM and deploy with Ansible → health
gate → switch → Grafana annotation. A separate rollback job swaps the listeners back.

### 3.3 Infrastructure (Terraform, 47 resources)
One VPC with two public subnets in two Availability Zones (no NAT Gateway: ~$30/month saved).
Security groups allow app traffic only from the ALB, and SSH and the test listener only from the
developer's IP. There are two target groups and two Auto Scaling Groups (blue and green; t3.micro,
min 1 / max 2). The ALB has a production listener on port 80 and a test listener on port 8080.
Also included: SSM parameters, the ECR repository, CloudWatch log group, alarms and SNS topic, and
four IAM identities with least privilege (instance role, Jenkins user, read-only Grafana user,
scoped Terraform runner policy).

### 3.4 Blue-Green deployment
`/splitease/live_color` says which colour is live; the other one is idle. A release goes to the idle
colour, and must pass **two** checks before the switch: (a) every target healthy for **5
consecutive checks**; (b) the test listener returns the **new build number** 5 times in a row. The
switch itself is two `ModifyListener` calls plus an SSM update. Because the old colour keeps
running, rollback is the same switch in reverse.

### 3.5 Self-healing
| Layer | Mechanism |
|---|---|
| Process | Docker `--restart unless-stopped` |
| Instance | ALB health check + ASG `health_check_type = ELB` → replacement, booted by user data into the version recorded in SSM |
| Capacity | Target tracking at 50% average CPU (1-minute detailed monitoring) |
| Release | Health gate and version gate before the switch; the idle colour's tag is restored on failure |

### 3.6 Monitoring
CloudWatch Logs (Docker `awslogs` driver), four alarms (CPU > 70% per ASG; unhealthy hosts > 0 per
target group) to SNS email, and a Grafana dashboard provisioned as code. It shows CPU and instances
per ASG, healthy/unhealthy hosts, requests per colour, response time, 5xx errors and app logs, with
Jenkins annotations at every switch.

### 3.7 Security (DevSecOps)
| Threat | Control |
|---|---|
| Leaked credentials in code | Gitleaks gate (full branch history); `.gitignore`; keys only in Jenkins Credentials / gitignored `.env`; Terraform never creates access keys |
| Vulnerable dependencies | Trivy gate (HIGH/CRITICAL with a fix), pinned dependencies, `--pull` |
| Over-privileged automation | Separate least-privilege identities; Jenkins may switch only our two listeners; Grafana is read-only |
| Network exposure | App port only from the ALB; SSH and 8080 only from one IP; HTTPS-only egress |
| Credential theft from containers | IMDSv2 required, hop limit 1 |
| Supply chain of the tooling itself | Jenkins image tools pinned and SHA-256 verified (Trivy itself was the target of a 2026 supply-chain attack) |
| Chaos endpoints abused | Disabled unless `CHAOS_MODE=true`, unit-tested |

## 4. Implementation
Built in 15 phases (0–14, see `CLAUDE.md` §9), each verified before the next. Every file has a
plain-English study note in `docs/notes/`, and the project history is in `PROGRESS.md` and the git log.

## 5. Testing and results
### 5.1 Unit tests
144 tests (v2): money maths and rounding properties for many totals and group sizes, invalid input,
all endpoints, and chaos endpoints returning 404 when disabled.

### 5.2 Security gates (real Jenkins runs)
| Branch | Result | Evidence |
|---|---|---|
| `demo/failing-test` | **Failed at Unit tests** | 31 failed, 113 passed; later stages skipped |
| `demo/fake-secret` | **Failed at Gitleaks** | `generic-api-key` in `app/payment_config.py`, value redacted |
| `demo/vulnerable-image` | **Failed at Trivy** | gunicorn 21.2.0: CVE-2024-1135, CVE-2024-6827 (HIGH); never pushed to ECR |
| `feature/v2`, `demo/bad-release` | Passed CI | release stages skipped (not `main`) |

During development Trivy also caught real issues in our *own* image: two HIGH `zlib1g` CVEs (fixed
by `apt-get upgrade`) and HIGH CVEs in pip's bundled libraries (fixed by removing pip). The final
image has **0** HIGH/CRITICAL findings.

### 5.3 Releases
| Build | What | Result | Duration |
|---|---|---|---|
| #8 | v1 → blue (first release) | Live | 724 s (included waiting for an instance replacement) |
| #9 | v2 → green | **Blocked by the version gate** (instance healthy but still on the old build); live untouched | 242 s |
| #10 | v2 → green | Live | 186 s |
| Rollback #1 | green → blue | Live on v1 | 154 s |
| #11 | v2.1 *bad release* → green | **Blocked by the health gate** (`ResponseCodeMismatch`); live untouched | 137 s |
| #12 | revert → green | Live | 193 s |
| #13 | chaos-enabled release → blue | Live | 191 s |

A normal release takes **about 3 minutes** from push to live traffic.

### 5.4 Self-healing
| Scenario | Observation |
|---|---|
| `/crash` | One HTTP 502 for ~2 s; Docker restart count 0 → 1; sequence visible in CloudWatch Logs |
| `docker stop` | ALB unhealthy after 47 s; ASG replaced the instance 1 min 47 s after the stop |
| Bad release (idle colour) | ASG replaced the failing instance ~90 s after it turned unhealthy; replacement healthy ~8 min later on the restored version |
| `/cpu` | ASG CPU 100%; scale-out to 2 instances ~4 min after the load started; second instance healthy ~8 min later |
| Alarms | Emails for green unhealthy hosts (bad release, docker stop), blue high CPU, and their recoveries |

### 5.5 Grafana (Phase 14)
Before it was committed, every dashboard panel was executed through Grafana's query API against the
real account (all panels returned data), and the annotation script was tested with a valid,
missing and wrong token and with Grafana down (always exit 0). *The end-to-end result (release
annotation and `/cpu` on the dashboard) is recorded in `PROGRESS.md` and the screenshots.*

## 6. Problems encountered and how they were solved
| Problem | Root cause | Fix |
|---|---|---|
| Trivy failed our first image | Base image older than Debian fixes; pip's vendored libraries | `apt-get upgrade`; remove pip after install |
| Gitleaks flagged a line of the Ansible inventory | Generic API-key rule false positive: the word "key" followed by a dotted, random-looking value | Rewrote the expression in bracket form `ec2_tags['Env']` (same meaning), amended before pushing |
| A single "healthy" poll could approve a bad release | The ALB reports the *old* container's state for up to 45 s | Require 5 consecutive healthy polls (60 s); fail fast on `ResponseCodeMismatch` (found with a mocked test) |
| First `terraform apply`: AccessDenied everywhere | The Terraform IAM user had read-only rights | Wrote a scoped policy (`terraform-runner-policy.json`), validated with IAM Access Analyzer and a policy simulation |
| `InvalidParameterValue` on security groups | Apostrophe not allowed in SG descriptions (not caught by `plan`) | Reworded; Terraform created only the missing resources |
| Instances replaced before they could ever become healthy | t3 standard credit mode has no launch credits: user data took 311 s at 72% CPU steal | Grace period 300 → 600 s (measured, not guessed) |
| Two builds for one commit | `pollSCM` and multibranch indexing both triggered | Only one trigger (branch indexing) |
| `IncompleteSignature` from AWS | Access key ID pasted together with the secret | Re-created a single key, printed one value per line |
| `Load key: error in libcrypto` in Ansible | SSH key pasted with CRLF / missing newline | Pipeline normalises the key; a pre-flight check fails clearly; re-entered with `clip.exe` |
| Grafana SEARCH panels failed | Grafana 13 needs the builder fields even in code mode | Added the empty builder fields; verified every panel via the API |

## 7. Cost
About **$0.08 per hour** while running (ALB ≈ $0.023, two t3.micro ≈ $0.022, four public IPv4 ≈
$0.02, EBS + detailed monitoring ≈ $0.01). Everything is destroyed after each session, so the build
and all demonstrations used about **$1** of free-plan credits. Without destroy it would be ≈
$55/month, which is why `terraform destroy` is a project rule.

## 8. Limitations
- HTTP only (no TLS); instances in public subnets (protected by security groups).
- Local Terraform state (single user); Jenkins and Grafana depend on the laptop being on.
- Zero-credit t3 instances boot slowly (~5–8 min), which lengthens instance replacement.
- The `/cpu` demo needs an instance that has accumulated CPU credits.

## 9. Future work
HTTPS with ACM, WAF, private subnets with VPC endpoints, Secrets Manager, remote Terraform state
with locking, an IAM permissions boundary, drift detection, SonarQube/Semgrep/OWASP dependency
scanning, canary releases, container orchestration (ECS/Kubernetes), and multi-region.

## 10. Conclusion
The project meets its objectives. Insecure or broken changes were stopped automatically at the
right gate. Good releases reached users in about three minutes with no downtime, and the one bad
release that passed CI was stopped before users saw it. Failures at the process, instance and
capacity level were repaired without anyone stepping in. The whole system can be rebuilt from git
with one `terraform apply` and torn down to zero cost with one `terraform destroy`.

## References
Jenkins Pipeline documentation · Gitleaks · Trivy · Terraform AWS provider · Ansible `amazon.aws`
collection · AWS documentation: Application Load Balancer, EC2 Auto Scaling, burstable performance
instances (CPU credits), CloudWatch, SSM Parameter Store · Grafana CloudWatch data source.
