output "alb_dns_name" {
  description = "DNS name del Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL del API Gateway"
  value       = "http://${aws_lb.main.dns_name}"
}

output "frontend_bucket_name" {
  description = "Nombre del bucket S3 del frontend"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_website_endpoint" {
  description = "Endpoint del website S3"
  value       = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "frontend_url" {
  description = "URL del frontend"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos RDS"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "rabbitmq_console_url" {
  description = "URL de la consola de RabbitMQ"
  value       = "http://${aws_lb.main.dns_name}/rabbitmq/"
}

output "ecr_api_gateway_repository_url" {
  description = "URL del repositorio ECR para API Gateway"
  value       = aws_ecr_repository.api_gateway.repository_url
}

output "ecr_worker_repository_url" {
  description = "URL del repositorio ECR para Worker"
  value       = aws_ecr_repository.worker.repository_url
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "aws_region" {
  description = "Region de AWS"
  value       = var.aws_region
}
