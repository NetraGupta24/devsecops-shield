# Launch templates: the "recipe" the Auto Scaling Groups use for every NEW
# instance (blue and green). User data boots each instance into the correct
# app version with nobody around.

# Latest Amazon Linux 2023 AMI, published by AWS in a public SSM parameter.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Public half of YOUR SSH key (the private half stays on your laptop and in
# the Jenkins Credentials store). Ansible logs in with it.
resource "aws_key_pair" "deploy" {
  key_name   = "${var.project}-deploy"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_launch_template" "app" {
  for_each = local.colors

  name                   = "${var.project}-${each.key}"
  description            = "SplitEase ${each.key} environment"
  image_id               = data.aws_ssm_parameter.al2023_ami.insecure_value
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deploy.key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  # t3 defaults to "unlimited", which can bill extra for sustained high CPU.
  # "standard" caps CPU at the baseline when credits run out: no surprise bills.
  credit_specification {
    cpu_credits = "standard"
  }

  # Detailed monitoring = 1-minute CPU metrics, so the scaling policy and the
  # CPU alarm react in ~3 minutes instead of ~15 (costs a few cents per day).
  monitoring {
    enabled = true
  }

  # IMDSv2 only, and a hop limit of 1 so containers can't read the instance's
  # credentials from the metadata service (only the host can).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    color              = each.key
    aws_region         = var.aws_region
    ecr_registry       = local.ecr_registry
    ecr_repository_url = aws_ecr_repository.app.repository_url
    log_group          = aws_cloudwatch_log_group.app.name
    param_prefix       = local.param_prefix
    app_port           = var.app_port
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project}-${each.key}"
      Project = var.project
      Env     = each.key
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name    = "${var.project}-${each.key}"
      Project = var.project
      Env     = each.key
    }
  }
}
