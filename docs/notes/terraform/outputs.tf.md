# `terraform/outputs.tf`

**What it does:** Prints useful values after `terraform apply` (and on `terraform output`): the live
URL (port 80), the test URL (port 8080), the ECR repository URL, the Jenkins IAM user name, the ASG
names and the SNS topic. No secrets are output.

Phase 14 added `grafana_iam_user` (the read-only user whose access key goes into `jenkins/.env`).
