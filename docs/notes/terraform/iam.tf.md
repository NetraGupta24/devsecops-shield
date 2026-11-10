# `terraform/iam.tf`

**What it does:** Creates two identities with **least-privilege** permissions.

**1. EC2 instance role** (`splitease-ec2-role`), attached via an *instance profile*. The servers get
temporary credentials automatically, so no keys are stored on them.
- ECR: log in and **pull** from the `splitease` repo only.
- SSM: `GetParameter` on `/splitease/*` only (read the image tag and chaos flag).
- CloudWatch Logs: write to `/splitease/app` only (the Docker `awslogs` driver).

**2. Jenkins IAM user** (`splitease-jenkins`):
- ECR: **push** to `splitease` only.
- SSM: get/put on `/splitease/*` only.
- ELB: `Describe*` and **`ModifyListener` on our two listeners only** (to switch traffic).
- `ec2:DescribeInstances` (Ansible dynamic inventory), `autoscaling:Describe*`.

**Why Terraform doesn't create the access key:** an access key created by Terraform would be stored
in the Terraform state file. Instead **you** create the key and paste it straight into Jenkins
Credentials, so it never touches disk in this project, git or chat. `force_destroy = true` lets
`terraform destroy` remove the user even though it has a key. That means you create a fresh key
after each `terraform apply`.

**Why not use your own admin keys in Jenkins?** If Jenkins were ever compromised, the attacker would
get only these narrow permissions, not your whole account.
