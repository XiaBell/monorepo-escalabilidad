resource "aws_db_subnet_group" "main" {
  name       = "${local.app_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.app_name}-db-subnet-group"
    }
  )
}

resource "aws_db_instance" "postgres" {
  identifier     = "${local.app_name}-postgres"
  engine         = "postgres"
  engine_version = "17.2"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "escalabilidad_db"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = false
  publicly_accessible    = true
  backup_retention_period = 0
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"

  skip_final_snapshot       = true
  final_snapshot_identifier = "${local.app_name}-postgres-final-snapshot"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  # Asegurar que la instancia esté disponible antes de continuar
  apply_immediately = true
  
  # Configuraciones adicionales para evitar timeouts
  deletion_protection = false
  skip_final_snapshot = true
  
  # Timeouts más largos
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.app_name}-postgres"
    }
  )
}
