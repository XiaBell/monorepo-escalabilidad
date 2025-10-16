terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "escalabilidad-universitario"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  app_name = "escalabilidad"
  common_tags = {
    Application = local.app_name
    Environment = var.environment
  }
}
