variable "aws_region" {
  description = "AWS region para desplegar recursos"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de despliegue"
  type        = string
  default     = "dev"
}

variable "availability_zones" {
  description = "Zonas de disponibilidad"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "CIDR block para VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_username" {
  description = "Usuario de base de datos PostgreSQL"
  type        = string
  default     = "escalabilidad_user"
  sensitive   = true
}

variable "db_password" {
  description = "Password de base de datos PostgreSQL"
  type        = string
  sensitive   = true
}

variable "rabbitmq_username" {
  description = "Usuario de RabbitMQ"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "rabbitmq_password" {
  description = "Password de RabbitMQ"
  type        = string
  sensitive   = true
}

variable "api_gateway_cpu" {
  description = "CPU para API Gateway (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "api_gateway_memory" {
  description = "Memoria para API Gateway en MB"
  type        = number
  default     = 512
}

variable "worker_cpu" {
  description = "CPU para Worker"
  type        = number
  default     = 256
}

variable "worker_memory" {
  description = "Memoria para Worker en MB"
  type        = number
  default     = 512
}

variable "worker_desired_count" {
  description = "Número de instancias del Worker"
  type        = number
  default     = 2
}

variable "api_gateway_desired_count" {
  description = "Número de instancias del API Gateway"
  type        = number
  default     = 2
}
