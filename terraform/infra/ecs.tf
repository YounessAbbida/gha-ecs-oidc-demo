locals {
  container_name = "app"
  container_port = 8080
}

resource "aws_ecs_cluster" "main" {
  name = var.project_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ---------------------------------------------------------------------------
# Task definition. Terraform registers the first revision only; after that the
# deploy workflow registers new revisions (new image tag) and points the
# service at them.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = local.container_name
    # Placeholder tag. No image exists with this tag; the first deploy replaces
    # it with the commit SHA. desired_count stays 0 until then.
    image     = "${aws_ecr_repository.app.repository_url}:bootstrap"
    essential = true
    user      = "10001:10001"

    readonlyRootFilesystem = true
    privileged             = false

    portMappings = [{
      containerPort = local.container_port
      protocol      = "tcp"
    }]

    linuxParameters = {
      capabilities = { drop = ["ALL"] }
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app"
  description = "App tasks: 8080 from the ALB only, HTTPS out"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from the ALB only"
  ip_protocol                  = "tcp"
  from_port                    = local.container_port
  to_port                      = local.container_port
  referenced_security_group_id = aws_security_group.alb.id
}

# HTTPS out through the NAT gateway: ECR image pulls (API + S3 layers) and
# CloudWatch Logs. Nothing else leaves the task.
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs (ECR, S3, CloudWatch Logs) via NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_ecs_service" "app" {
  name                   = var.project_name
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.app.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  platform_version       = "LATEST"
  enable_execute_command = false

  # Gives a new task time to start before ALB health checks can kill it.
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.container_name
    container_port   = local.container_port
  }

  # A failed rollout (task never becomes healthy) is stopped and rolled back
  # to the last working task definition.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # The deploy workflow owns the task definition revision from the first
  # deploy on. Without this, every terraform apply would roll the service back
  # to the :bootstrap placeholder.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http]
}
