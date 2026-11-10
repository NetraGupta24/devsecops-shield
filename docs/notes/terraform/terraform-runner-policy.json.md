# `terraform/terraform-runner-policy.json`

**What it is:** The IAM policy that lets *your own* IAM user (the one Terraform runs as) create this
project's infrastructure. You attach it once in the IAM console. Terraform can't attach it itself,
because a user that could grant itself permissions would be a security hole.

**Why it was needed:** the first `terraform apply` failed with `AccessDenied` on every resource. The
user `vle8-terraform-user` only had `ReadOnlyAccess` (which is why `terraform plan` worked) and an
EC2 read-only policy from another project.

**What it allows (least privilege, but practical):**

| Statement | Scope |
|---|---|
| EC2, Elastic Load Balancing, Auto Scaling: all actions | **Only in ap-south-1** (`aws:RequestedRegion` condition) |
| ECR | Only the `splitease` repository |
| IAM | Only roles/users/instance profiles named `splitease-*` (so it can't touch your other IAM users) |
| `iam:CreateServiceLinkedRole` | Only for ELB and Auto Scaling. AWS creates these roles the first time an account uses an ALB or ASG |
| SSM Parameter Store | Only `/splitease/*` |
| CloudWatch Logs | Only log groups `/splitease/*` |
| CloudWatch alarms | Only alarms `splitease-*` (incl. `SetAlarmState`, used to test the alarm email) |
| SNS | Only topics `splitease-*` |

Reading/listing everything (for `terraform plan` and the console) still comes from `ReadOnlyAccess`.

**Checked with IAM Access Analyzer** (`aws accessanalyzer validate-policy`): no findings.

**Known trade-off (viva question):** anyone who can create IAM roles and write their policies can,
in principle, give those roles more power. The policy limits this to `splitease-*` names, but this
user's keys must still be protected like an admin's. A stricter setup would add an IAM
*permissions boundary*, which is listed as future work.

**The account ID isn't in the file** (`*` is used instead), so it can safely live in a public repo.
