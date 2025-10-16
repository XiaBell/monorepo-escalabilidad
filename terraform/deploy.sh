#!/bin/bash

set -e

echo "=================================================="
echo "Deploy Script - Sistema de Escalabilidad AWS"
echo "=================================================="
echo ""

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Verificar si estamos en el directorio terraform
if [ ! -f "main.tf" ]; then
    echo -e "${RED}Error: Este script debe ejecutarse desde el directorio terraform${NC}"
    exit 1
fi

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI no está instalado${NC}"
    exit 1
fi

# Verificar Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform no está instalado${NC}"
    exit 1
fi

# Verificar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker no está instalado${NC}"
    exit 1
fi

echo -e "${GREEN}Verificaciones iniciales completadas${NC}"
echo ""

# Paso 1: Inicializar Terraform
echo -e "${YELLOW}Paso 1: Inicializando Terraform...${NC}"
terraform init
echo ""

# Paso 2: Validar configuración
echo -e "${YELLOW}Paso 2: Validando configuración...${NC}"
terraform validate
echo ""

# Paso 3: Planificar
echo -e "${YELLOW}Paso 3: Generando plan de ejecución...${NC}"
terraform plan -out=tfplan
echo ""

# Confirmar aplicación
read -p "¿Deseas aplicar este plan? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Despliegue cancelado"
    exit 0
fi

# Paso 4: Aplicar infraestructura
echo -e "${YELLOW}Paso 4: Aplicando infraestructura...${NC}"
terraform apply tfplan
echo ""

# Obtener outputs
echo -e "${GREEN}Obteniendo información de la infraestructura...${NC}"
ECR_API=$(terraform output -raw ecr_api_gateway_repository_url)
ECR_WORKER=$(terraform output -raw ecr_worker_repository_url)
AWS_REGION=$(terraform output -json | jq -r '.alb_dns_name.value' | cut -d'.' -f2)
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo -e "${YELLOW}Paso 5: Construyendo y pusheando imágenes Docker...${NC}"

# Login a ECR
echo "Autenticando con ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com

# Construir y pushear API Gateway
echo "Construyendo API Gateway..."
cd ../api-gateway
docker build -t escalabilidad/api-gateway:latest .
docker tag escalabilidad/api-gateway:latest $ECR_API:latest
docker push $ECR_API:latest

# Construir y pushear Worker
echo "Construyendo Worker..."
cd ../worker
docker build -t escalabilidad/worker:latest .
docker tag escalabilidad/worker:latest $ECR_WORKER:latest
docker push $ECR_WORKER:latest

cd ../terraform

echo ""
echo -e "${YELLOW}Paso 6: Subiendo frontend a S3...${NC}"
BUCKET_NAME=$(terraform output -raw frontend_bucket_name)
aws s3 sync ../frontend/ s3://$BUCKET_NAME/ --exclude "*.md" --exclude ".git*"

echo ""
echo -e "${YELLOW}Paso 7: Reiniciando servicios ECS...${NC}"
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
aws ecs update-service --cluster $CLUSTER_NAME --service escalabilidad-api-gateway --force-new-deployment --region $AWS_REGION
aws ecs update-service --cluster $CLUSTER_NAME --service escalabilidad-worker --force-new-deployment --region $AWS_REGION

echo ""
echo -e "${GREEN}=================================================="
echo "Despliegue Completado"
echo "==================================================${NC}"
echo ""
echo "URLs de acceso:"
echo "  API Gateway: $(terraform output -raw alb_url)"
echo "  Frontend: $(terraform output -raw frontend_url)"
echo "  RabbitMQ Console: $(terraform output -raw rabbitmq_console_url)"
echo ""
echo "Siguiente paso:"
echo "  1. Conectarse a RDS y ejecutar database/init.sql"
echo "  2. Esperar 5-10 minutos para que los servicios estén saludables"
echo ""
