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
