# `terraform/user_data.sh.tftpl`

**What it does:** The script every **new** instance runs once at first boot (as root). Terraform's
`templatefile()` fills in `${color}`, `${aws_region}` and the other values for each colour.

**Steps:**
1. `dnf install docker` (with retries), start Docker.
2. Read **this colour's image tag** and the **chaos flag** from SSM, using the instance role (no
   keys).
3. If the tag is `none` (nothing released yet), stop. There's nothing to run.
4. Log in to ECR, pull the image, and run it with:
   - `--restart unless-stopped`: Docker restarts the container if the app crashes (self-healing
     level 1);
   - `--log-driver awslogs`: logs go to CloudWatch;
   - `-p 5000:5000` and `-e CHAOS_MODE=...`.

**Why user data AND Ansible?** They solve different problems. **Ansible** updates instances that are
*already running* when Jenkins releases. **User data** handles instances the ASG creates *later*
(scaling, replacing a failed server) with nobody around. Both read the same SSM parameter, so they
always agree on the version.

Output is in `/var/log/cloud-init-output.log` on the instance.
