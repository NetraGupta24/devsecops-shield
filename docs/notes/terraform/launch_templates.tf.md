# `terraform/launch_templates.tf`

**What it does:** One **launch template per colour**, the recipe for every *new* instance an ASG
creates.
- **AMI:** latest Amazon Linux 2023, looked up from AWS's public SSM parameter.
- **t3.micro** with `credit_specification { cpu_credits = "standard" }`. t3 defaults to *unlimited*,
  which bills extra for sustained high CPU. *Standard* caps CPU at the baseline when credits run out,
  so there are no surprise charges. (Trade-off: no launch credits, so boot is slower.)
- `monitoring { enabled = true }`: 1-minute CPU metrics, so scaling and alarms react in minutes.
  Costs a few cents per instance-day.
- **IMDSv2 required, hop limit 1:** the instance metadata service (which hands out the role's
  credentials) needs a session token, and containers (one network hop away) can't reach it.
- **Encrypted gp3 root volume**.
- **Key pair** `splitease-deploy`: your public key, so Ansible can SSH in.
- **Tags** `Project=splitease`, `Env=<colour>`. Ansible's dynamic inventory uses these to find
  "the green servers".
- **User data:** `user_data.sh.tftpl` rendered with this colour's values.
