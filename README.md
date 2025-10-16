# Sistema de Escalabilidad y Latencia - Arquitectura de Microservicios

Proyecto universitario que demuestra los conceptos de **escalabilidad** y **latencia** mediante una arquitectura de microservicios con patrón **Productor/Consumidor Asíncrono**.

## Arquitectura del Sistema

Este sistema implementa una **separación estricta de responsabilidades** entre dos microservicios:

### Componentes

1. **API Gateway** (FastAPI)
   - Responsabilidad: Gestionar el ciclo de vida de las consultas
   - Crea registros en la tabla `consulta` con estado `pending`
   - Publica mensajes en RabbitMQ
   - Responde a peticiones de polling del frontend
   - **NO tiene acceso a la tabla `producto`**

2. **Worker** (Python asíncrono)
   - Responsabilidad: Procesar consultas y acceder a datos de productos
   - Consume mensajes de RabbitMQ
   - **Es el ÚNICO con acceso a la tabla `producto`**
   - Actualiza la tabla `consulta` con los resultados

3. **Frontend** (HTML/CSS/JS)
   - Interfaz de usuario
   - Crea consultas asíncronas
   - Hace polling para obtener resultados

4. **PostgreSQL**
   - Tabla `producto`: Catálogo de productos (solo accesible por Worker)
   - Tabla `consulta`: Registros de consultas y resultados (Gateway crea, Worker actualiza)

5. **RabbitMQ**
   - Message broker para desacoplar Gateway y Worker
   - Permite escalado independiente

### Flujo de Datos

```
Frontend → API Gateway → RabbitMQ → Worker → PostgreSQL
    ↓                                    ↓
    ← ← ← ← ← Polling ← ← ← ← ← ← ← ← ← ←
```

1. Frontend envía petición POST `/consultar` al API Gateway
2. API Gateway crea registro en tabla `consulta` (estado: `pending`)
3. API Gateway publica mensaje en cola RabbitMQ
4. API Gateway responde inmediatamente con `consulta_id`
5. Worker consume mensaje de RabbitMQ
6. Worker consulta tabla `producto` en PostgreSQL
7. Worker actualiza tabla `consulta` con resultado (estado: `completed`)
8. Frontend hace polling a `/consultar/{id}` hasta obtener resultado

## Stack Tecnológico

- **Backend**: Python 3.12
- **Framework**: FastAPI
- **Base de Datos**: PostgreSQL 17
- **Message Broker**: RabbitMQ 3.13 (con interfaz de gestión)
- **Librerías Asíncronas**: `aio-pika==9.5.1`, `asyncpg`
- **Orquestación**: Docker & Docker Compose

## Instalación y Ejecución

### Prerrequisitos

- Docker
- Docker Compose

### Pasos

1. **Clonar el repositorio**

```bash
cd proyecto-escalabilidad-u
```

2. **Crear archivo de variables de entorno**

```bash
cp .env.example .env
```

3. **Iniciar todos los servicios**

```bash
docker-compose up --build
```

4. **Acceder a la aplicación**

- **Frontend**: http://localhost
- **API Gateway**: http://localhost:8000
- **Documentación API**: http://localhost:8000/docs
- **RabbitMQ Management**: http://localhost:15672 (usuario: `admin`, password: `admin123`)

## Uso del Sistema

### Listar Todos los Productos

1. Click en "Listar Todos los Productos"
2. El sistema crea una consulta asíncrona
3. Espera mientras el Worker procesa
4. Los resultados aparecen automáticamente

### Buscar Producto por Código

1. Ingresa un código (ej: `PROD001`)
2. Click en "Buscar por Código"
3. El sistema consulta de forma asíncrona
4. El resultado aparece cuando esté listo

## Escalado

### Escalar Workers

Para demostrar escalabilidad, puedes agregar más workers:

```bash
docker-compose up --scale worker=3
```

Esto crea 3 instancias del worker que procesan mensajes en paralelo desde RabbitMQ.

### Observar el Comportamiento

1. Abre la interfaz de RabbitMQ: http://localhost:15672
2. Ve a la pestaña "Queues"
3. Observa cómo los mensajes se distribuyen entre workers
4. Crea múltiples consultas desde el frontend
5. Observa cómo se procesan concurrentemente

## Conceptos Demostrados

### Escalabilidad

- **Horizontal**: Puedes agregar más workers sin modificar código
- **Desacoplamiento**: Gateway y Worker son independientes
- **Balanceo de carga**: RabbitMQ distribuye mensajes entre workers

### Latencia

- **Respuesta inmediata**: El API Gateway no bloquea al usuario
- **Procesamiento asíncrono**: El trabajo pesado se hace en background
- **Polling**: El frontend consulta periódicamente por resultados

### Patrón Productor/Consumidor

- **Productor**: API Gateway publica mensajes
- **Cola**: RabbitMQ almacena mensajes de forma persistente
- **Consumidor**: Worker procesa mensajes a su propio ritmo

## Estructura del Proyecto

```
proyecto-escalabilidad-u/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── .dockerignore
├── README.md
│
├── database/
│   └── init.sql
│
├── api-gateway/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py
│   └── schemas.py
│
├── worker/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── worker.py
│
└── frontend/
    ├── index.html
    ├── style.css
    └── app.js
```

## API Endpoints

### POST /consultar

Crea una consulta asíncrona.

**Body:**
```json
{
  "tipo_consulta": "listar_todos"
}
```
o
```json
{
  "tipo_consulta": "buscar_codigo",
  "codigo": "PROD001"
}
```

**Respuesta:**
```json
{
  "consulta_id": 1,
  "status": "pending",
  "message": "Consulta encolada exitosamente"
}
```

### GET /consultar/{consulta_id}

Obtiene el estado y resultado de una consulta.

**Respuesta:**
```json
{
  "consulta_id": 1,
  "tipo_consulta": "listar_todos",
  "status": "completed",
  "resultado": [...],
  "created_at": "2024-01-01T12:00:00",
  "processed_at": "2024-01-01T12:00:05"
}
```

### GET /health

Verifica el estado de los servicios.

## Monitoreo

### Logs

Ver logs en tiempo real:

```bash
# Todos los servicios
docker-compose logs -f

# Solo API Gateway
docker-compose logs -f api-gateway

# Solo Worker
docker-compose logs -f worker
```

### Métricas de RabbitMQ

Accede a http://localhost:15672 para ver:
- Mensajes en cola
- Tasa de publicación/consumo
- Workers conectados
- Mensajes procesados

## Troubleshooting

### Los contenedores no inician

```bash
docker-compose down -v
docker-compose up --build
```

### RabbitMQ no está listo

Espera unos segundos. RabbitMQ tarda en inicializar completamente.

### Error de conexión a PostgreSQL

Verifica que el puerto 5432 no esté siendo usado por otra instancia de PostgreSQL.

## Limpieza

Detener y eliminar todos los contenedores y volúmenes:

```bash
docker-compose down -v
```

## Licencia

MIT
