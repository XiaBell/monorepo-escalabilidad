# Log groups eliminados - no se necesitan sin roles IAM

resource "aws_ecs_cluster" "main" {
  name = "${local.app_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "api_gateway" {
  family                   = "${local.app_name}-api-gateway"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_gateway_cpu
  memory                   = var.api_gateway_memory
  # Usa un rol existente permitido por el entorno Voclabs (definido en iam.tf)
  execution_role_arn       = data.aws_iam_role.existing_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "api-gateway"
      image     = "${aws_ecr_repository.api_gateway.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DATABASE_URL"
          value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.endpoint}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"
        },
        {
          name  = "RABBITMQ_URL"
          value = "amqp://${var.rabbitmq_username}:${var.rabbitmq_password}@${aws_lb.rabbitmq_nlb.dns_name}:5672"
        },
        {
          name  = "QUEUE_NAME"
          value = "consulta_queue"
        }
      ]

      # logConfiguration eliminado - no se puede usar sin execution role

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.app_name}-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = data.aws_iam_role.existing_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = "${aws_ecr_repository.worker.repository_url}:latest"
      essential = true

      environment = [
        {
          name  = "DATABASE_URL"
          value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.endpoint}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"
        },
        {
          name  = "RABBITMQ_URL"
          value = "amqp://${var.rabbitmq_username}:${var.rabbitmq_password}@${aws_lb.rabbitmq_nlb.dns_name}:5672"
        },
        {
          name  = "QUEUE_NAME"
          value = "consulta_queue"
        }
      ]

      # logConfiguration eliminado - no se puede usar sin execution role
    }
  ])

  tags = local.common_tags
}

# Task Definition para RabbitMQ en ECS
resource "aws_ecs_task_definition" "rabbitmq" {
  family                   = "${local.app_name}-rabbitmq"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.existing_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "rabbitmq"
      image     = "rabbitmq:3.13-management-alpine"
      essential = true

      portMappings = [
        {
          containerPort = 5672
          protocol      = "tcp"
        },
        {
          containerPort = 15672
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "RABBITMQ_DEFAULT_USER"
          value = var.rabbitmq_username
        },
        {
          name  = "RABBITMQ_DEFAULT_PASS"
          value = var.rabbitmq_password
        }
      ]

      # Sin logConfiguration
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "api_gateway" {
  name            = "${local.app_name}-api-gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api_gateway.arn
  desired_count   = var.api_gateway_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_gateway.arn
    container_name   = "api-gateway"
    container_port   = 8000
  }

  depends_on = [
    aws_lb_listener.http,
    aws_db_instance.postgres,
    aws_security_group.rds
  ]

  tags = local.common_tags
}

# Service para RabbitMQ
resource "aws_ecs_service" "rabbitmq" {
  name            = "${local.app_name}-rabbitmq"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.rabbitmq_ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rabbitmq_tg.arn
    container_name   = "rabbitmq"
    container_port   = 15672
  }

  # Eliminado Service Discovery (Cloud Map) para evitar AccessDenied

  depends_on = [
    aws_lb_listener.http
  ]

  tags = local.common_tags
}

resource "aws_ecs_service" "worker" {
  name            = "${local.app_name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_db_instance.postgres,
    aws_security_group.rds
  ]

  tags = local.common_tags
}

# Eliminados recursos de Service Discovery (Cloud Map) por restricciones del entorno
