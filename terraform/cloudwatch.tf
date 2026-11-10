# CloudWatch: logs from the containers, plus alarms that email you via SNS.

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project}/app"
  retention_in_days = 7
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

# AWS sends a confirmation email; alarms are delivered only after you click it.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# High CPU on a colour: average > 70% for 3 minutes.
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = local.colors

  alarm_name          = "${var.project}-${each.key}-high-cpu"
  alarm_description   = "Average CPU of the ${each.key} Auto Scaling Group is above 70% for 3 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.app[each.key].name }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Unhealthy instance behind the ALB: at least one target failing /health for 2 minutes.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  for_each = local.colors

  alarm_name        = "${var.project}-${each.key}-unhealthy-hosts"
  alarm_description = "At least one ${each.key} target is failing the ALB /health check"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "UnHealthyHostCount"
  dimensions = {
    TargetGroup  = aws_lb_target_group.app[each.key].arn_suffix
    LoadBalancer = aws_lb.app.arn_suffix
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
