# Security groups are virtual firewalls.
#   ALB SG : 80 from anywhere (the public site), 8080 from YOUR IP only (test listener)
#   App SG : 5000 from the ALB SG only, 22 (SSH for Ansible) from YOUR IP only

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "SplitEase ALB: HTTP 80 from anywhere, test listener 8080 from the owner's IP"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Production listener"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_test" {
  security_group_id = aws_security_group.alb.id
  description       = "Test listener (idle colour), owner only"
  cidr_ipv4         = var.my_ip
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB forwards requests and health checks to the app"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "SplitEase instances: app port from the ALB only, SSH from the owner's IP"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App traffic from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  description       = "SSH for Ansible, owner only"
  cidr_ipv4         = var.my_ip
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# Outbound HTTPS only: dnf repositories, ECR, S3 (image layers), SSM and
# CloudWatch Logs are all HTTPS. (DNS, NTP and instance metadata use
# link-local addresses that security groups don't filter.)
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs and package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
