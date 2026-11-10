output "app_url" {
  description = "Production URL (port 80 -> live colour)"
  value       = "http://${aws_lb.app.dns_name}/"
}

output "test_url" {
  description = "Test URL (port 8080 -> idle colour), reachable from your IP only"
  value       = "http://${aws_lb.app.dns_name}:8080/"
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "jenkins_iam_user" {
  description = "Create an access key for this user yourself and store it ONLY in Jenkins Credentials"
  value       = aws_iam_user.jenkins.name
}

output "autoscaling_groups" {
  value = { for color, asg in aws_autoscaling_group.app : color => asg.name }
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "initial_live_color" {
  value = local.initial_live_color
}
