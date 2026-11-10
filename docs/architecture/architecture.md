# DevSecOps Shield: architecture

Everything on this page is **implemented and was demonstrated on AWS** (2026-11-10), unless it's in
the "Future work" section. GitHub renders the diagrams; for the report, screenshot them or paste the
code into https://mermaid.live.

## 1. System overview

```mermaid
flowchart LR
    dev([Developer]) -->|git push| gh[(GitHub<br/>devsecops-shield)]

    subgraph laptop["Student laptop (WSL2 + Docker Desktop)"]
        direction TB
        jenkins["Jenkins LTS (Docker)<br/>pytest · Gitleaks · Docker · Trivy<br/>AWS CLI · Ansible + aws_ec2 inventory"]
        grafana["Grafana 13.2.5 (Docker)<br/>dashboard as code"]
        tf["Terraform<br/>(run by the student)"]
        jenkins -->|annotations<br/>http://grafana:3000| grafana
    end

    gh -->|"polled every minute<br/>(branch indexing)"| jenkins

    subgraph aws["AWS ap-south-1"]
        direction TB
        ecr[("ECR: splitease<br/>immutable tags, keep 5")]
        ssm[("SSM Parameter Store<br/>live_color · blue/green image_tag · chaos_mode")]

        subgraph vpc["VPC 10.20.0.0/16 · 2 public subnets in 2 AZs · no NAT"]
            alb{{"Application Load Balancer<br/>:80 production · :8080 test (your IP only)"}}
            tgb["Target group blue"]
            tgg["Target group green"]
            subgraph asgb["ASG blue (min 1 / max 2)"]
                eb["EC2 t3.micro AL2023<br/>Docker: splitease container<br/>Gunicorn :5000, non-root"]
            end
            subgraph asgg["ASG green (min 1 / max 2)"]
                eg["EC2 t3.micro AL2023<br/>Docker: splitease container"]
            end
            alb --> tgb --> eb
            alb --> tgg --> eg
        end

        cw["CloudWatch<br/>logs /splitease/app · metrics · 4 alarms"]
        sns["SNS topic<br/>splitease-alerts"]
        cw --> sns
    end

    user([Users]) -->|HTTP :80| alb
    jenkins -->|push approved image| ecr
    jenkins -->|read/write tags + live colour| ssm
    jenkins -->|"ModifyListener (switch 80/8080)"| alb
    jenkins -->|Ansible over SSH :22 your IP only| eb
    jenkins -->|Ansible over SSH| eg
    tf -->|creates / destroys| aws
    eb -->|pull image| ecr
    eg -->|pull image| ecr
    eb -->|"user data reads tag, chaos flag"| ssm
    eb -->|awslogs driver| cw
    eg -->|awslogs driver| cw
    grafana -->|read-only IAM user| cw
    sns -->|email| inbox([Student inbox])
```

**Who does what**

| Component | Role in this project |
|---|---|
| GitHub | Source of truth. `main` + feature/demo branches |
| Jenkins (local, Docker) | Multibranch pipeline. CI on every branch; release (ECR + Blue-Green) on `main` only |
| pytest / Gitleaks / Trivy | Quality gate / Security Gate 1 (secrets) / Security Gate 2 (image CVEs) |
| ECR | Stores only images that passed every gate (`build-<N>`, immutable) |
| Terraform | Creates all 47 AWS resources (VPC, SGs, ALB, ASGs, IAM, SSM, CloudWatch, SNS, ECR) |
| SSM Parameter Store | Which colour is live, which image each colour runs, chaos flag |
| Ansible | Updates the *running* instances of the idle colour (`deploy.yml`, dynamic inventory) |
| EC2 user data | Boots *new* instances (scaling/replacement) into the version recorded in SSM |
| ALB + target groups | Health checks (`/health`) and instant Blue-Green switching |
| Auto Scaling Groups | Replace unhealthy/terminated instances; scale out on CPU > 50% |
| CloudWatch + SNS | Logs, metrics, alarms, email |
| Grafana (local, Docker) | Dashboard over CloudWatch; Jenkins annotates each switch/rollback |

## 2. Pipeline (Jenkinsfile)

```mermaid
flowchart TD
    A[Checkout] --> B[Unit tests<br/>pytest]
    B --> C[Gitleaks<br/>full branch history]
    C --> D["Docker build<br/>splitease:build-N, --pull"]
    D --> E["Trivy<br/>HIGH/CRITICAL with fix => fail"]
    E -->|branch != main| Z([CI passed: stop here])
    E -->|main| F[Push to ECR]
    F --> G["Find idle colour<br/>SSM live_color"]
    G --> H["Deploy to idle colour<br/>1) SSM image_tag  2) Ansible deploy.yml"]
    H --> I{"Health check<br/>all idle targets healthy 5x in a row<br/>AND :8080 /version == N"}
    I -->|pass| J["Switch traffic<br/>:80 -> idle, :8080 -> old<br/>SSM live_color; Grafana annotation"]
    I -->|fail| K["Restore idle SSM tag<br/>:80 never touched"]
    B -. fail .-> X([Stop: nothing built or deployed])
    C -. fail .-> X
    E -. fail .-> X
```

## 3. Blue-Green release and rollback

```mermaid
sequenceDiagram
    participant J as Jenkins
    participant S as SSM
    participant A as Ansible
    participant E as Idle EC2 (e.g. green)
    participant L as ALB
    participant G as Grafana
    J->>S: get /splitease/live_color (blue) => idle = green
    J->>S: put /splitease/green/image_tag = build-N
    J->>A: ansible-playbook deploy.yml -e target_color=green
    A->>E: docker pull + run build-N, check /version
    loop every 15 s until 5 healthy checks in a row
        J->>L: describe-target-health (green)
    end
    J->>L: GET :8080/version (5x == N)
    J->>L: modify-listener :80 -> green, :8080 -> blue
    J->>S: put live_color = green
    J->>G: annotation "Release build-N: blue -> green"
    Note over J,L: Rollback job = same switch in reverse<br/>(blue is still running the previous build)
```

## 4. Self-healing layers

```mermaid
flowchart LR
    c1["App process crash<br/>(/crash)"] --> r1["Docker restart policy<br/>unless-stopped<br/>(~2 s, same instance)"]
    c2["Container down<br/>(docker stop)"] --> d2["ALB /health fails<br/>3 x 15 s"] --> r2["ASG (ELB health check)<br/>replaces instance<br/>user data boots right version"]
    c3["Instance terminated"] --> r3["ASG below desired<br/>launches replacement"]
    c4["CPU > 50%<br/>(/cpu)"] --> r4["Target tracking<br/>adds 2nd instance, removes it later"]
    c5["Bad release"] --> r5["Idle health check fails<br/>no switch; tag restored"]
    c6["Problem after release"] --> r6["Rollback job<br/>swap listeners back"]
```

## 5. Network and security boundaries

| From → To | Allowed | Enforced by |
|---|---|---|
| Internet → ALB :80 | yes | ALB security group |
| Internet → ALB :8080 (idle colour) | **student IP only** | ALB SG (`var.my_ip`) |
| ALB → EC2 :5000 | yes | App SG references ALB SG |
| Internet → EC2 :5000 | **no** | App SG (only from ALB SG) |
| Laptop (Jenkins/Ansible) → EC2 :22 | **student IP only** | App SG |
| EC2 → internet | HTTPS (443) only | App SG egress |
| Container → instance metadata (credentials) | **no** | IMDSv2 required, hop limit 1 |

Identities (least privilege): EC2 instance role (pull own repo, read `/splitease/*`, write own log
group) · Jenkins IAM user (push own repo, `/splitease/*` params, switch *our two* listeners) ·
Grafana IAM user (read-only) · student's Terraform user (`SplitEaseTerraformRunner`: EC2/ELB/ASG in
ap-south-1, everything else only `splitease-*`). No access keys exist in the repo or Terraform state.

## 6. Future work (not implemented)

HTTPS with ACM certificate · WAF · private subnets + NAT/VPC endpoints · Secrets Manager · remote
Terraform state (S3 + DynamoDB lock) · IAM permissions boundary for the Terraform runner · drift
detection · SonarQube/Semgrep/OWASP dependency scanning · canary releases · Kubernetes/ECS ·
multi-region. Prometheus was deliberately not used: Grafana reads CloudWatch directly.
