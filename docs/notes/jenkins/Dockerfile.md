# `jenkins/Dockerfile`

**What it does:** Builds *our own* Jenkins image: the official Jenkins LTS plus every command-line
tool the pipeline calls.

| Tool | Why the pipeline needs it |
|---|---|
| Docker CLI + buildx | `docker build`, `docker push` (talks to Docker Desktop through the socket) |
| Python 3 + venv | runs pytest in a clean virtual environment per build |
| Gitleaks 8.30.1 | Security Gate 1: secret scanning |
| Trivy 0.76.1 | Security Gate 2: image vulnerability scanning |
| AWS CLI v2 | ECR login, SSM parameters, ALB listener switching |
| Ansible core 2.21 + `amazon.aws` + boto3 | deploys to EC2. boto3 lets the `aws_ec2` inventory plugin find instances |
| jq, ssh client | read JSON from the AWS CLI; Ansible connects over SSH |

**Key ideas:**
- **Multi-stage build:** `FROM docker:29.9.3-cli AS dockercli` is used only to *copy* the Docker
  binaries out of Docker's official image. That is simpler and safer than adding a package repository.
- **Pinned versions + SHA-256 checks:** every download is checked against a known checksum
  (`sha256sum -c`). If the file was tampered with or corrupted, the image build fails. This is
  supply-chain security for our *own* tooling.
- **Ansible in a virtualenv (`/opt/ansible`):** keeps its Python packages separate from the OS.
  ansible-core 2.21 was chosen because it can still manage servers that use Python 3.9 (Amazon Linux
  2023's system Python).
- **Plugins installed at build time** (`jenkins-plugin-cli`) and **jobs copied in as code** (see
  `jobs/`), so a fresh Jenkins needs very little clicking.
- Ends with `USER jenkins`, so Jenkins doesn't run as root.

**How it connects:** `jenkins/docker-compose.yml` builds and runs this image. The `Jenkinsfile` uses
the tools.
