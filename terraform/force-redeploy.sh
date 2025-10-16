#!/bin/bash

# Script para forzar redeploy de ECS services después de cambios en Security Groups
echo "=== FORZANDO REDEPLOY DE ECS SERVICES ==="

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Obtener valores de Terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
AWS_REGION=$(terraform output -raw aws_region)

echo -e "${YELLOW}Cluster: $CLUSTER_NAME${NC}"
echo -e "${YELLOW}Region: $AWS_REGION${NC}"

# Forzar redeploy de API Gateway
echo -e "${YELLOW}Forzando redeploy de API Gateway...${NC}"
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service escalabilidad-api-gateway \
  --force-new-deployment \
  --region $AWS_REGION \
  --output table

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ API Gateway redeploy iniciado${NC}"
else
  echo -e "${RED}✗ Error en redeploy de API Gateway${NC}"
fi

# Forzar redeploy de Worker
echo -e "${YELLOW}Forzando redeploy de Worker...${NC}"
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service escalabilidad-worker \
  --force-new-deployment \
  --region $AWS_REGION \
  --output table

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Worker redeploy iniciado${NC}"
else
  echo -e "${RED}✗ Error en redeploy de Worker${NC}"
fi

# Verificar estado de los servicios
echo -e "${YELLOW}Verificando estado de servicios...${NC}"
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services escalabilidad-api-gateway escalabilidad-worker \
  --region $AWS_REGION \
  --query 'services[].{ServiceName:serviceName,Status:status,RunningCount:runningCount,DesiredCount:desiredCount}' \
  --output table

echo -e "${GREEN}=== REDEPLOY COMPLETADO ===${NC}"
echo -e "${YELLOW}Espera 2-3 minutos para que las nuevas tasks tomen el Security Group correcto.${NC}"
