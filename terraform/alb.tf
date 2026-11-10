# Application Load Balancer: the single public entry point.
#   Listener 80   (production) -> the LIVE colour's target group
#   Listener 8080 (test)       -> the IDLE colour's target group (your IP only)
# Jenkins switches the listeners during a Blue-Green release, so Terraform is
# told to ignore their default_action after creating them.

resource "aws_lb" "app" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Security hardening: drop requests with malformed HTTP headers.
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  for_each = local.colors

  name        = "${var.project}-${each.key}"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  # How long the ALB keeps sending in-flight requests to a target that is
  # being removed (default 300 s). 30 s makes switches and replacements faster.
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2 # 2 passes in a row (30 s) -> healthy
    unhealthy_threshold = 3 # 3 failures in a row (45 s) -> unhealthy
  }

  tags = { Env = each.key }
}

resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[local.initial_live_color].arn
  }

  lifecycle {
    ignore_changes = [default_action] # Jenkins owns this after creation
  }
}

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.app.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[local.initial_idle_color].arn
  }

  lifecycle {
    ignore_changes = [default_action] # Jenkins owns this after creation
  }
}
