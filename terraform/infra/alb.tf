resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb"
  description = "Public HTTP to the ALB"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  # checkov:skip=CKV_AWS_260: Port 80 is open to the internet on purpose: this is the public entry point of the demo.
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to the app tasks only"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_lb" "app" {
  # checkov:skip=CKV_AWS_91: ALB access logs need a dedicated S3 bucket; out of scope for a few-hour demo.
  # checkov:skip=CKV_AWS_150: Deletion protection is off so terraform destroy works in one step.
  # checkov:skip=CKV2_AWS_20: HTTP only: no domain or ACM certificate in this demo (see README, production notes).
  # checkov:skip=CKV2_AWS_28: No WAF in front of a demo that serves a static JSON response.
  name                       = var.project_name
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.vpc.public_subnets
  drop_invalid_header_fields = true
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "app" {
  name        = var.project_name
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  # Faster deploys and teardown; the app has no long-lived connections.
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  # checkov:skip=CKV_AWS_2: HTTP only: no domain or ACM certificate in this demo (see README, production notes).
  # checkov:skip=CKV_AWS_103: TLS policy does not apply to an HTTP listener.
  # checkov:skip=CKV2_AWS_74: TLS policy does not apply to an HTTP listener.
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
