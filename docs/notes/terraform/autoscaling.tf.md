# `terraform/autoscaling.tf`

**What it does:** One **Auto Scaling Group per colour**: min 1, desired 1, max 2, spread over both
subnets/AZs, registered in that colour's target group.

**Self-healing settings:**
- `health_check_type = "ELB"`: the ASG trusts the **ALB health check**. If `/health` fails (for
  example the container was stopped), the ASG terminates the instance and launches a new one. User
  data then boots it with the right version.
- `health_check_grace_period = 600`: don't judge a new instance until it has had time to boot. Measured: ~440 s on a zero-credit t3.micro (see `variables.tf.md`).
- If an instance is terminated, the ASG notices it is below desired capacity and launches a
  replacement.

**Scaling policy (target tracking):** keep the ASG's **average CPU at 50%**. When `/cpu` pushes it
higher, AWS adds a second instance (max 2). When CPU stays low for ~15 min, it removes it again.

**Other details:**
- `wait_for_capacity_timeout = "0"`: before the first release there is no image, so instances
  can't be healthy. Terraform shouldn't wait for them.
- `ignore_changes = [desired_capacity]`: the scaling policy changes desired capacity, and Terraform
  must not fight it.
