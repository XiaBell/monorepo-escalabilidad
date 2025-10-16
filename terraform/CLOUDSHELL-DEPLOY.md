# Guía de Deployment desde AWS CloudShell

Esta guía explica cómo desplegar el sistema completo desde AWS CloudShell.

## Prerrequisitos

1. Acceso a AWS CloudShell (disponible en la consola de AWS)
2. Permisos IAM necesarios para crear recursos (VPC, ECS, RDS, MQ, S3, ECR, etc.)
3. Repositorio clonado en CloudShell

**Nota:** AWS CloudShell ya incluye Docker y Terraform preinstalados, no necesitas instalar nada adicional.

## Flujo de Credenciales

### Cómo se manejan las credenciales

Las credenciales de RabbitMQ y PostgreSQL se definen en `terraform.tfvars` y Terraform las inyecta automáticamente en los contenedores ECS:

```
terraform.tfvars
    ↓
Terraform variables (var.db_password, var.rabbitmq_password)
    ↓
RDS Instance (línea 13 de rds.tf)
Amazon MQ Broker (línea 15 de mq.tf)
ECS Task Definitions (líneas 51-55 y 103-107 de ecs.tf)
    ↓
Environment variables en contenedores:
  - DATABASE_URL=postgresql://user:PASSWORD@endpoint/db
  - RABBITMQ_URL=amqps://user:PASSWORD@endpoint:5671
```

**Importante:** Las credenciales NUNCA se hardcodean en el código fuente. Se pasan dinámicamente desde Terraform.

## Pasos para Desplegar

### 1. Abrir AWS CloudShell

1. Inicia sesión en la consola de AWS
2. Click en el ícono de CloudShell (terminal) en la barra superior
3. Espera a que CloudShell inicie (tarda ~30 segundos)

### 2. Clonar el Repositorio

```bash
git clone <tu-repositorio-url>
cd proyecto-escalabilidad-u/terraform
```

### 3. Configurar Credenciales

Crea el archivo `terraform.tfvars` con tus credenciales seguras:

```bash
nano terraform.tfvars
```

Contenido (edita las contraseñas):

```hcl
aws_region = "us-east-1"
environment = "dev"
availability_zones = ["us-east-1a", "us-east-1b"]

# IMPORTANTE: Cambia estas contraseñas
db_username = "escalabilidad_user"
db_password = "TU_PASSWORD_SEGURO_AQUI_MIN_8_CHARS"

rabbitmq_username = "admin"
rabbitmq_password = "TU_PASSWORD_SEGURO_AQUI_MIN_12_CHARS"

# Configuración de recursos ECS
api_gateway_cpu           = 256
api_gateway_memory        = 512
api_gateway_desired_count = 2

worker_cpu           = 256
worker_memory        = 512
worker_desired_count = 2
```

**Requisitos de contraseñas:**
- **PostgreSQL**: Mínimo 8 caracteres
- **RabbitMQ**: Mínimo 12 caracteres, debe incluir mayúsculas, minúsculas y números

Guarda con `Ctrl+O`, `Enter`, `Ctrl+X`

### 4. Ejecutar el Script de Deployment

```bash
chmod +x cloudshell-deploy.sh
./cloudshell-deploy.sh
```

### 5. Proceso de Deployment

El script ejecutará automáticamente:

1. ✅ **Verificación de herramientas** (Docker y Terraform ya vienen en CloudShell)
2. ✅ **Inicialización de Terraform** (`terraform init`)
3. ✅ **Validación** (`terraform validate`)
4. ✅ **Generación del plan** (`terraform plan`)
5. ⏳ **Aplicación de infraestructura** (15-20 minutos)
   - VPC, subnets, NAT gateways
   - Security groups
   - RDS PostgreSQL
   - Amazon MQ RabbitMQ
   - ECS Cluster
   - Application Load Balancer
   - S3 bucket
   - ECR repositories
6. ✅ **Construcción de imágenes Docker**
   - API Gateway
   - Worker
7. ✅ **Push a ECR**
8. ✅ **Upload del frontend a S3**
9. ✅ **Redespliegue de servicios ECS**

### 6. Inicializar la Base de Datos

Después del deployment, ejecuta el script SQL:

```bash
# Instalar cliente PostgreSQL
sudo yum install postgresql15 -y

# Obtener endpoint de RDS (el script te lo mostrará)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)

# Ejecutar script de inicialización
PGPASSWORD='TU_PASSWORD' psql \
    -h $RDS_ENDPOINT \
    -U escalabilidad_user \
    -d escalabilidad_db \
    -f ../database/init.sql
```

Deberías ver:

```
CREATE TABLE
CREATE TABLE
INSERT 0 10
```

### 7. Verificar el Deployment

Espera 5-10 minutos para que los servicios ECS estén saludables, luego:

```bash
# Verificar health del API
curl $(terraform output -raw alb_url)/health

# Debería responder:
# {"status":"healthy","database":"connected","rabbitmq":"connected"}
```

### 8. Acceder a la Aplicación

```bash
# Ver todas las URLs
terraform output

# URLs disponibles:
# - frontend_url: Interfaz de usuario
# - alb_url: API Gateway
# - rabbitmq_console_url: Consola de RabbitMQ
```

## Verificación de Credenciales

### Verificar que RabbitMQ recibió las credenciales

```bash
# Obtener la URL de la consola de RabbitMQ
terraform output rabbitmq_console_url

# Abrir en el navegador e iniciar sesión con:
# Usuario: admin (o el que configuraste en terraform.tfvars)
# Password: el que configuraste en terraform.tfvars
```

### Verificar que los contenedores tienen las variables correctas

```bash
# Ver variables de entorno del API Gateway
aws ecs describe-task-definition \
    --task-definition escalabilidad-api-gateway \
    --query 'taskDefinition.containerDefinitions[0].environment' \
    --output table

# Deberías ver DATABASE_URL y RABBITMQ_URL
```

### Verificar logs de los contenedores

```bash
# Logs del API Gateway
aws logs tail /ecs/escalabilidad/api-gateway --follow

# Logs del Worker
aws logs tail /ecs/escalabilidad/worker --follow

# Buscar mensajes de conexión exitosa:
# - "Connected to database"
# - "Connected to RabbitMQ"
```

## Troubleshooting

### Error: "Docker no está disponible"

AWS CloudShell incluye Docker por defecto. Si ves este error, simplemente reinicia tu sesión de CloudShell:

1. Cierra la pestaña de CloudShell
2. Abre CloudShell nuevamente desde la consola de AWS
3. Vuelve a clonar el repositorio o navega al directorio

### Error: "Falló la construcción de imagen"

Verifica que los Dockerfiles y requirements.txt estén presentes:

```bash
ls -la ../api-gateway/
ls -la ../worker/
```

### Error: "ECS tasks no inician"

1. Verifica los logs en CloudWatch:
   ```bash
   aws logs tail /ecs/escalabilidad/api-gateway --since 30m
   ```

2. Verifica que las imágenes existen en ECR:
   ```bash
   aws ecr describe-images --repository-name escalabilidad-api-gateway
   aws ecr describe-images --repository-name escalabilidad-worker
   ```

3. Verifica security groups:
   ```bash
   terraform show | grep security_group
   ```

### Error: "No se puede conectar a RDS"

RDS está en subnet privada, solo accesible desde:
- ECS tasks (API Gateway y Worker)
- CloudShell (si haces psql)

Verifica que el security group permita conexiones desde CloudShell:

```bash
# Obtener tu IP pública
curl https://checkip.amazonaws.com

# Verificar reglas del security group de RDS
aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=*rds*" \
    --query 'SecurityGroups[].IpPermissions'
```

Si no puedes conectarte desde CloudShell, es normal. Los contenedores ECS sí pueden.

### Error: "RabbitMQ no conecta"

Amazon MQ usa **amqps://** (TLS obligatorio). Verifica:

1. Que la URL empiece con `amqps://` (no `amqp://`)
2. Que el puerto sea 5671 (no 5672)
3. Logs del Worker:
   ```bash
   aws logs tail /ecs/escalabilidad/worker --since 10m
   ```

## Limpieza (Destruir Infraestructura)

Para eliminar todos los recursos:

```bash
# 1. Vaciar bucket S3 (requerido antes de destruir)
BUCKET_NAME=$(terraform output -raw frontend_bucket_name)
aws s3 rm s3://$BUCKET_NAME/ --recursive

# 2. Destruir infraestructura
terraform destroy

# Confirma con 'yes' cuando se te pida
```

**Costo de dejar corriendo:** ~$145 USD/mes

## Escalado Post-Deployment

### Escalar Workers

```bash
# Editar terraform.tfvars
nano terraform.tfvars

# Cambiar worker_desired_count = 5

# Aplicar cambios
terraform apply
```

### Escalar API Gateway

```bash
# Editar terraform.tfvars
nano terraform.tfvars

# Cambiar api_gateway_desired_count = 4

# Aplicar cambios
terraform apply
```

## Monitoreo

### Ver todas las tareas en ejecución

```bash
aws ecs list-tasks --cluster escalabilidad-cluster

# Ver detalles de una tarea
aws ecs describe-tasks \
    --cluster escalabilidad-cluster \
    --tasks <task-arn>
```

### Ver métricas en RabbitMQ

Accede a la consola de RabbitMQ (output `rabbitmq_console_url`) y verás:

- Mensajes en la cola `consulta_queue`
- Tasa de publicación (API Gateway)
- Tasa de consumo (Workers)
- Conexiones activas

### Ver logs en tiempo real

```bash
# API Gateway
aws logs tail /ecs/escalabilidad/api-gateway --follow

# Worker
aws logs tail /ecs/escalabilidad/worker --follow
```

## Resumen del Flujo de Credenciales

```
Usuario configura:
  terraform.tfvars
      ↓
Terraform crea:
  - RDS con password
  - Amazon MQ con password
  - ECS Task Definitions con variables de entorno
      ↓
ECS ejecuta contenedores:
  - Leen DATABASE_URL (incluye password)
  - Leen RABBITMQ_URL (incluye password)
      ↓
Aplicación funciona:
  - API Gateway conecta a RDS y RabbitMQ
  - Worker conecta a RDS y RabbitMQ
```

**Las credenciales NUNCA están hardcodeadas. Todo es dinámico desde Terraform.**
