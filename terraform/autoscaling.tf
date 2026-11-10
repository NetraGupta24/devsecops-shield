# Auto Scaling Groups (one per colour): keep 1-2 healthy instances running.
#  - health_check_type = "ELB": an instance that fails the ALB's /health check
#    is terminated and replaced (self-healing).
#  - Target tracking: add an instance when average CPU > 50%, remove it later.

resource "aws_autoscaling_group" "app" {
  for_each = local.colors

  name                = "${var.project}-${each.key}"
  min_size            = 1
  desired_capacity    = 1
  max_size            = 2
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.app[each.key].arn]

  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = var.health_check_grace_period

  # Don't make `terraform apply` wait for healthy instances: before the first
  # release there is no image in ECR, so instances can't be healthy yet.
  wait_for_capacity_timeout = "0"

  launch_template {
    id      = aws_launch_template.app[each.key].id
    version = "$Latest"
  }

  # Free 1-minute group metrics (shown on the ASG "Monitoring" tab).
  enabled_metrics = ["GroupDesiredCapacity", "GroupInServiceInstances", "GroupTotalInstances"]

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = false # instances get their tags from the launch template
  }

  tag {
    key                 = "Env"
    value               = each.key
    propagate_at_launch = false
  }

  lifecycle {
    # Auto Scaling changes desired_capacity itself; Terraform must not reset it.
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "cpu" {
  for_each = local.colors

  name                   = "${var.project}-${each.key}-cpu50"
  autoscaling_group_name = aws_autoscaling_group.app[each.key].name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}
