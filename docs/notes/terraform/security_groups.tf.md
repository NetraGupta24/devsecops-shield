# `terraform/security_groups.tf`

**What it does:** Two firewalls (security groups).

| SG | Inbound | Outbound |
|---|---|---|
| **ALB SG** | 80 from anywhere; **8080 from your IP only** | 5000 to the app SG only |
| **App SG** | **5000 from the ALB SG only**; **22 from your IP only** | 443 (HTTPS) only |

**Key ideas:**
- **Security-group referencing:** "5000 from the ALB SG" means only the load balancer can reach the
  app, even though the instances have public IPs. Users can't bypass the ALB.
- **Least privilege outbound:** the instances only need HTTPS (dnf repos, ECR, S3, SSM,
  CloudWatch). DNS, time sync and instance metadata use link-local addresses that SGs don't filter.
- The **test listener 8080** exposes the *idle* (not yet live) version, so only you and Jenkins on
  your laptop (same IP) may use it.

## Lesson learned: a bug `plan` couldn't catch
The first real apply failed with `InvalidParameterValue: Invalid security group description`.
Security-group descriptions may only contain `a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*`, and ours said
"owner**'**s IP" (an apostrophe). `terraform validate` and `terraform plan` don't check this,
because only the AWS API knows the rule, so the error appeared at `apply`. The 23 resources created
before the error stayed. After the fix, `terraform plan` showed only the 22 missing ones. That is
Terraform's state at work: it remembers what already exists and creates only the difference.
