# `terraform/provider.tf`

**What it does:** Tells Terraform to use the **AWS provider** (the plugin that knows how to call AWS
APIs), version `~> 6.0`, in region `ap-south-1`. It also:
- adds the tags `Project=splitease` and `ManagedBy=terraform` to every resource (`default_tags`),
  so you can find everything on the bill;
- reads your AWS account ID (`aws_caller_identity`);
- defines shared values (`locals`): the two colours, the ECR registry address, the SSM prefix, and
  the **initial live colour**.

**Why the initial live colour is green:** before the first release nothing runs anywhere. Marking
*green* as "live" makes the first pipeline run deploy to **blue** (the idle colour) and switch
traffic to it. That matches the plan: v1 goes to Blue, then v2 goes to Green.

**What is Terraform?** *Infrastructure as Code*: you describe the AWS resources you want in `.tf`
files, `terraform plan` shows what would change, and `terraform apply` makes AWS match the files.
`terraform destroy` deletes it all again, which is how this project saves credits.
