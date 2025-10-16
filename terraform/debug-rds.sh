#!/bin/bash

# Script de debug para verificar conectividad RDS
echo "=== DEBUG RDS CONECTIVITY ==="

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}1. Verificando outputs de Terraform...${NC}"
terraform output rds_endpoint
terraform output rds_port
terraform output rds_database_name
terraform output rds_username

echo -e "${YELLOW}2. Verificando estado de RDS...${NC}"
aws rds describe-db-instances --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port,PubliclyAccessible:PubliclyAccessible}' --output table

echo -e "${YELLOW}3. Verificando Security Groups...${NC}"
RDS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*rds*" --query 'SecurityGroups[0].GroupId' --output text)
echo "RDS Security Group ID: $RDS_SG_ID"
aws ec2 describe-security-groups --group-ids $RDS_SG_ID --query 'SecurityGroups[0].IpPermissions' --output table

echo -e "${YELLOW}4. Verificando VPC y Subnets...${NC}"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*vpc*" --query 'Vpcs[0].VpcId' --output text)
echo "VPC ID: $VPC_ID"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].{SubnetId:SubnetId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone}' --output table

echo -e "${YELLOW}5. Verificando DNS resolution...${NC}"
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
echo "Resolviendo $RDS_ENDPOINT..."
nslookup $RDS_ENDPOINT || echo -e "${RED}ERROR: No se puede resolver el endpoint${NC}"

echo -e "${YELLOW}6. Probando conectividad con telnet...${NC}"
RDS_PORT=$(terraform output -raw rds_port)
echo "Probando conexión a $RDS_ENDPOINT:$RDS_PORT..."
timeout 10 telnet $RDS_ENDPOINT $RDS_PORT && echo -e "${GREEN}✓ Conexión exitosa${NC}" || echo -e "${RED}✗ Timeout o conexión fallida${NC}"

echo -e "${YELLOW}7. Verificando ECS Tasks...${NC}"
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
echo "Cluster: $CLUSTER_NAME"
aws ecs list-services --cluster $CLUSTER_NAME --output table
aws ecs describe-services --cluster $CLUSTER_NAME --services $(aws ecs list-services --cluster $CLUSTER_NAME --query 'serviceArns[0]' --output text) --query 'services[0].{ServiceName:serviceName,Status:status,RunningCount:runningCount,DesiredCount:desiredCount}' --output table

echo -e "${YELLOW}8. Verificando logs de ECS...${NC}"
aws logs describe-log-groups --log-group-name-prefix "/ecs/" --query 'logGroups[].logGroupName' --output table

echo -e "${GREEN}=== DEBUG COMPLETADO ===${NC}"
