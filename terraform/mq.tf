resource "aws_lb" "rabbitmq_nlb" {
  name               = "${local.app_name}-rabbitmq-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  tags = merge(
    local.common_tags,
    { Name = "${local.app_name}-rabbitmq-nlb" }
  )
}

resource "aws_lb_target_group" "rabbitmq_amqp_tg" {
  name        = "${local.app_name}-rabbitmq-amqp-tg"
  port        = 5672
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    port                = "5672"
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(
    local.common_tags,
    { Name = "${local.app_name}-rabbitmq-amqp-tg" }
  )
}

resource "aws_lb_listener" "rabbitmq_amqp" {
  load_balancer_arn = aws_lb.rabbitmq_nlb.arn
  port              = 5672
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rabbitmq_amqp_tg.arn
  }
}
resource "aws_mq_broker" "rabbitmq" {
  broker_name = "${local.app_name}-rabbitmq"

  engine_type        = "RabbitMQ"
  engine_version     = "3.13"
  host_instance_type = "mq.t3.micro"
  deployment_mode    = "SINGLE_INSTANCE"

  publicly_accessible = false
  subnet_ids          = [aws_subnet.private[0].id]
  security_groups     = [aws_security_group.rabbitmq.id]

  user {
    username = var.rabbitmq_username
    password = var.rabbitmq_password
  }

  logs {
    general = true
  }

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.app_name}-rabbitmq"
    }
  )
}
