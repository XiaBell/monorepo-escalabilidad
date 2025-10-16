#!/bin/bash

set -e

echo "=================================================="
echo "Deploy desde AWS CloudShell"
echo "Sistema de Escalabilidad Universitario"
echo "=================================================="
echo ""
echo -e "${YELLOW}ARQUITECTURA ACTUALIZADA (v2.0):${NC}"
echo "• RabbitMQ en ECS (no Amazon MQ)"
echo "• ECR repositorios públicos (sin roles IAM)"
echo "• Sin logs CloudWatch (sin execution roles)"
echo "• Service Discovery para comunicación interna"
echo ""

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Verificar que estamos en CloudShell
if [ -z "$AWS_EXECUTION_ENV" ]; then
    echo -e "${YELLOW}Advertencia: No parece estar ejecutándose en CloudShell${NC}"
    echo "Este script está optimizado para AWS CloudShell"
    read -p "¿Deseas continuar de todas formas? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        exit 0
    fi
fi

# Verificar directorio
if [ ! -f "main.tf" ]; then
    echo -e "${RED}Error: Ejecuta este script desde el directorio terraform/${NC}"
    exit 1
fi

echo -e "${GREEN}Paso 1: Verificando herramientas...${NC}"

# Verificar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker no está disponible${NC}"
    exit 1
fi

# Verificar Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform no está disponible${NC}"
    exit 1
fi

echo "Docker version: $(docker --version)"
echo "Terraform version: $(terraform version | head -n1)"
echo ""

# Verificar si existe terraform.tfvars
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}No se encontró terraform.tfvars${NC}"
    echo "Creando desde terraform.tfvars.example..."

    if [ -f "terraform.tfvars.example" ]; then
        cp terraform.tfvars.example terraform.tfvars
        echo ""
        echo -e "${RED}IMPORTANTE: Debes editar terraform.tfvars con tus passwords${NC}"
        echo "Ejecuta: nano terraform.tfvars"
        echo ""
        read -p "Presiona Enter cuando hayas configurado terraform.tfvars..."
    else
        echo -e "${RED}Error: No existe terraform.tfvars.example${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Paso 2: Inicializando Terraform...${NC}"
terraform init
echo ""

echo -e "${GREEN}Paso 3: Validando configuración...${NC}"
terraform validate
echo ""

echo -e "${GREEN}Paso 4: Generando plan...${NC}"
terraform plan -out=tfplan
echo ""

read -p "¿Aplicar este plan? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cancelado"
    exit 0
fi

echo -e "${GREEN}Paso 5: Aplicando infraestructura (esto puede tardar 15-20 min)...${NC}"
terraform apply tfplan
echo ""

# Obtener información
echo -e "${GREEN}Obteniendo outputs...${NC}"
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_API=$(terraform output -raw ecr_api_gateway_repository_url)
ECR_WORKER=$(terraform output -raw ecr_worker_repository_url)
BUCKET_NAME=$(terraform output -raw frontend_bucket_name)

echo ""
echo -e "${GREEN}Paso 6: Construyendo imágenes Docker...${NC}"

# Login a ECR
echo "Autenticando con ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com

# Construir y pushear API Gateway
echo "Construyendo API Gateway..."
cd ../api-gateway
if docker build -t escalabilidad/api-gateway:latest .; then
    docker tag escalabilidad/api-gateway:latest $ECR_API:latest
    echo "Pusheando imagen API Gateway a ECR..."
    docker push $ECR_API:latest
else
    echo -e "${RED}Error: Falló la construcción de la imagen API Gateway${NC}"
    exit 1
fi

# Construir y pushear Worker
echo "Construyendo Worker..."
cd ../worker
if docker build -t escalabilidad/worker:latest .; then
    docker tag escalabilidad/worker:latest $ECR_WORKER:latest
    echo "Pusheando imagen Worker a ECR..."
    docker push $ECR_WORKER:latest
else
    echo -e "${RED}Error: Falló la construcción de la imagen Worker${NC}"
    exit 1
fi

cd ../terraform

echo ""
echo -e "${GREEN}Paso 7: Subiendo frontend a S3...${NC}"
aws s3 sync ../frontend/ s3://$BUCKET_NAME/ \
    --exclude "*.md" \
    --exclude ".git*" \
    --exclude ".DS_Store"

echo ""
echo -e "${GREEN}Paso 8: Forzando redespliegue de servicios ECS...${NC}"
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)

echo "Actualizando API Gateway service..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service escalabilidad-api-gateway \
    --force-new-deployment \
    --region $AWS_REGION > /dev/null

echo "Actualizando Worker service..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service escalabilidad-worker \
    --force-new-deployment \
    --region $AWS_REGION > /dev/null

echo "Actualizando RabbitMQ service..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service escalabilidad-rabbitmq \
    --force-new-deployment \
    --region $AWS_REGION > /dev/null

echo ""
echo -e "${GREEN}=================================================="
echo "Despliegue Completado Exitosamente"
echo "==================================================${NC}"
echo ""
echo "URLs de Acceso:"
echo "  Frontend:    $(terraform output -raw frontend_url)"
echo "  API Gateway: $(terraform output -raw alb_url)"
echo "  RabbitMQ:    $(terraform output -raw rabbitmq_console_url)"
echo ""
echo -e "${YELLOW}ARQUITECTURA ACTUALIZADA:${NC}"
echo ""
echo "✅ RabbitMQ ahora corre en ECS (no Amazon MQ)"
echo "✅ ECR repositorios son públicos (sin roles IAM)"
echo "✅ Sin logs en CloudWatch (sin execution roles)"
echo "✅ Service Discovery: rabbitmq.local"
echo ""
echo -e "${YELLOW}IMPORTANTE - Siguiente Paso:${NC}"
echo ""
echo "1. Conectarse a RDS y ejecutar el script de inicialización:"
echo ""
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
echo "   RDS Endpoint: $RDS_ENDPOINT"
echo ""
echo "   Desde CloudShell ejecuta:"
echo "   sudo yum install postgresql15 -y"
echo "   PGPASSWORD='TU_PASSWORD' psql -h $RDS_ENDPOINT -U escalabilidad_user -d escalabilidad_db -f ../database/init.sql"
echo ""
echo "2. Esperar 5-10 minutos para que los servicios ECS estén saludables"
echo ""
echo "3. Verificar health del API:"
echo "   curl \$(terraform output -raw alb_url)/health"
echo ""
echo "4. Verificar RabbitMQ Management:"
echo "   curl \$(terraform output -raw rabbitmq_console_url)"
echo ""
echo "5. Monitorear servicios ECS:"
echo "   aws ecs list-services --cluster \$CLUSTER_NAME --region \$AWS_REGION"
echo ""
echo -e "${GREEN}Deployment finalizado.${NC}"
