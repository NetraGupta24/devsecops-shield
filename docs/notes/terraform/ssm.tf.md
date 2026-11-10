# `terraform/ssm.tf`

**What it does:** Creates 4 **SSM Parameter Store** parameters (standard tier = free). They are the
pipeline's shared memory, the single source of truth about what runs where:

| Parameter | Initial value | Changed by |
|---|---|---|
| `/splitease/live_color` | `green` (see provider.tf) | Jenkins switch / rollback |
| `/splitease/blue/image_tag` | `none` | Jenkins deploy |
| `/splitease/green/image_tag` | `none` | Jenkins deploy |
| `/splitease/chaos_mode` | `false` | you (for the chaos demos) |

**Why SSM and not a file or Jenkins variable?** New instances launched by Auto Scaling at any time
must find out which version to run *by themselves*. User data reads `/splitease/<colour>/image_tag`
at boot. Jenkins, Ansible and user data all read the same values.

`lifecycle { ignore_changes = [value] }`: Terraform creates them, then leaves the values alone.
Otherwise every `terraform apply` would reset them to the initial values.
