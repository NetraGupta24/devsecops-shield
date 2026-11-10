# `terraform/variables.tf`

**What it does:** Declares the inputs of the Terraform configuration. Your real values go in
`terraform.tfvars` (gitignored).

| Variable | Meaning |
|---|---|
| `my_ip` | Your public IP `/32`. Only it may SSH (22) and use the test listener (8080). Validated to be a single address |
| `alert_email` | Receives CloudWatch alarm emails |
| `instance_type` | `t3.micro` (validation allows only t3.micro / t3.small, the Free-plan types) |
| `ssh_public_key_path` | Public key uploaded as the EC2 key pair |
| `health_check_grace_period` | 300 s. How long a new instance may boot before failed health checks count |

**Why the grace period is 300 s and not 180 s:** t3 instances in *standard* credit mode start with
**zero CPU credits** (AWS gives launch credits only to t2). A brand-new instance therefore runs at
its baseline speed (10% of each vCPU) while user data installs Docker and pulls the image. If the
grace period is too short, the ASG kills instances that are still booting, launches new ones, and
the same thing happens again.
