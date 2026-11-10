# IAM: least-privilege permissions.
#  1) EC2 instance role  - what the SERVERS may do (pull images, read SSM, write logs)
#  2) Jenkins IAM user   - what the PIPELINE may do (push images, switch traffic)
# Terraform itself runs as YOUR own IAM user (never the root account).

locals {
  splitease_params_arn = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter${local.param_prefix}/*"
}

# ---------------------------------------------------------------------------
# 1) EC2 instance role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project}-ec2-role"
  description        = "SplitEase instances: pull from ECR, read /splitease/* SSM parameters, write CloudWatch Logs"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ec2_permissions" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this API does not support resource-level permissions
  }

  statement {
    sid = "EcrPullSplitEaseOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "ReadSplitEaseParameters"
    actions   = ["ssm:GetParameter"]
    resources = [local.splitease_params_arn]
  }

  statement {
    sid       = "WriteAppLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "ec2" {
  name   = "${var.project}-ec2-permissions"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_permissions.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ---------------------------------------------------------------------------
# 2) Jenkins IAM user. Terraform creates the user and its policy but NOT an
#    access key: you create the key yourself and paste it straight into the
#    Jenkins Credentials store, so the secret never appears in Terraform state,
#    files, or chat.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "jenkins" {
  name = "${var.project}-jenkins"

  # Allows `terraform destroy` to delete the user even though it has an access key.
  force_destroy = true
}

data "aws_iam_policy_document" "jenkins" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushSplitEaseOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "ReadWriteSplitEaseParameters"
    actions   = ["ssm:GetParameter", "ssm:PutParameter"]
    resources = [local.splitease_params_arn]
  }

  statement {
    sid       = "DescribeLoadBalancing"
    actions   = ["elasticloadbalancing:Describe*"]
    resources = ["*"] # Describe* calls do not support resource-level permissions
  }

  statement {
    sid       = "SwitchSplitEaseListenersOnly"
    actions   = ["elasticloadbalancing:ModifyListener"]
    resources = [aws_lb_listener.prod.arn, aws_lb_listener.test.arn]
  }

  statement {
    sid       = "AnsibleInventoryAndAsgInfo"
    actions   = ["ec2:DescribeInstances", "autoscaling:Describe*"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "jenkins" {
  name   = "${var.project}-jenkins-pipeline"
  user   = aws_iam_user.jenkins.name
  policy = data.aws_iam_policy_document.jenkins.json
}

# ---------------------------------------------------------------------------
# 3) Grafana IAM user (Phase 14): READ-ONLY access to CloudWatch metrics and
#    the SplitEase logs, for the local Grafana dashboard. Like the Jenkins user,
#    no access key is created here: you create it yourself and put it only in
#    the gitignored jenkins/.env file.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "grafana" {
  name          = "${var.project}-grafana"
  force_destroy = true
}

data "aws_iam_policy_document" "grafana" {
  statement {
    sid = "ReadCloudWatchMetricsAndAlarms"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
    ]
    resources = ["*"] # these read APIs do not support resource-level permissions
  }

  statement {
    sid       = "ListLogGroupsAndQueryResults"
    actions   = ["logs:DescribeLogGroups", "logs:GetQueryResults", "logs:StopQuery"]
    resources = ["*"] # account-level calls (no resource-level permissions)
  }

  statement {
    sid = "QuerySplitEaseLogsOnly"
    actions = [
      "logs:StartQuery",
      "logs:GetLogGroupFields",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.app.arn,
      "${aws_cloudwatch_log_group.app.arn}:*",
    ]
  }

  statement {
    sid       = "ResolveResourceNamesForDashboards"
    actions   = ["ec2:DescribeRegions", "ec2:DescribeInstances", "ec2:DescribeTags", "tag:GetResources"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "grafana" {
  name   = "${var.project}-grafana-readonly"
  user   = aws_iam_user.grafana.name
  policy = data.aws_iam_policy_document.grafana.json
}
