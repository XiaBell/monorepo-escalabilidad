"""
API Gateway - Sistema de Escalabilidad
Responsabilidad: Gestionar el ciclo de vida de las consultas (crear y reportar estado)
NO tiene acceso a la tabla 'producto'
"""

import os
import json
from contextlib import asynccontextmanager
from typing import Optional

import asyncpg
from aio_pika import connect_robust, Message, DeliveryMode
from aio_pika.abc import AbstractRobustConnection, AbstractRobustChannel
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

from schemas import ConsultaRequest, ConsultaCreateResponse, ConsultaStatusResponse


DATABASE_URL = os.getenv("DATABASE_URL")
RABBITMQ_URL = os.getenv("RABBITMQ_URL")
QUEUE_NAME = os.getenv("QUEUE_NAME", "consulta_queue")


class AppState:
    db_pool: Optional[asyncpg.Pool] = None
    rabbitmq_connection: Optional[AbstractRobustConnection] = None
    rabbitmq_channel: Optional[AbstractRobustChannel] = None


app_state = AppState()


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("Iniciando API Gateway...")

    try:
        app_state.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=5, max_size=20)
        print("Conexión a PostgreSQL establecida")
    except Exception as e:
        print(f"Error conectando a PostgreSQL: {e}")
        app_state.db_pool = None  # Permitir que la app inicie y reporte unhealthy en /health

    try:
        app_state.rabbitmq_connection = await connect_robust(RABBITMQ_URL)
        app_state.rabbitmq_channel = await app_state.rabbitmq_connection.channel()
        await app_state.rabbitmq_channel.declare_queue(QUEUE_NAME, durable=True)
        print(f"Conexión a RabbitMQ establecida (cola: {QUEUE_NAME})")
    except Exception as e:
        print(f"Error conectando a RabbitMQ: {e}")
        app_state.rabbitmq_connection = None
        app_state.rabbitmq_channel = None

    print("API Gateway listo\n")
    yield

    print("\nCerrando conexiones...")
    if app_state.rabbitmq_channel:
        await app_state.rabbitmq_channel.close()
    if app_state.rabbitmq_connection:
        await app_state.rabbitmq_connection.close()
    if app_state.db_pool:
        await app_state.db_pool.close()
    print("Conexiones cerradas")


app = FastAPI(
    title="API Gateway - Sistema de Escalabilidad",
    description="Gateway para gestión de consultas asíncronas de productos",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {"service": "API Gateway", "status": "online", "version": "1.0.0"}


@app.get("/health")
async def health_check():
    """Health check del API Gateway"""
    health = {"api": "healthy", "database": "unknown", "message_broker": "unknown"}

    try:
        async with app_state.db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        health["database"] = "healthy"
    except Exception as e:
        health["database"] = f"unhealthy: {str(e)}"

    try:
        if app_state.rabbitmq_connection and not app_state.rabbitmq_connection.is_closed:
            health["message_broker"] = "healthy"
        else:
            health["message_broker"] = "unhealthy"
    except Exception as e:
        health["message_broker"] = f"unhealthy: {str(e)}"

    return health


@app.post("/consultar", response_model=ConsultaCreateResponse, status_code=status.HTTP_202_ACCEPTED)
async def crear_consulta(request: ConsultaRequest):
    """
    Crea una consulta asíncrona:
    1. Crea un registro en la tabla 'consulta' con estado 'pending'
    2. Publica mensaje en RabbitMQ con el ID de la consulta
    3. Retorna el ID para que el frontend pueda hacer polling

    Nota: Este endpoint NO accede a la tabla 'producto'
    """
    if request.tipo_consulta not in ["listar_todos", "buscar_codigo"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="tipo_consulta debe ser 'listar_todos' o 'buscar_codigo'"
        )

    if request.tipo_consulta == "buscar_codigo" and not request.codigo:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El campo 'codigo' es requerido para tipo_consulta 'buscar_codigo'"
        )

    try:
        async with app_state.db_pool.acquire() as conn:
            consulta_id = await conn.fetchval(
                """
                INSERT INTO consulta (codigo_buscado, tipo_consulta, status)
                VALUES ($1, $2, $3)
                RETURNING id
                """,
                request.codigo if request.tipo_consulta == "buscar_codigo" else None,
                request.tipo_consulta,
                "pending"
            )

        mensaje = json.dumps({
            "consulta_id": consulta_id,
            "tipo_consulta": request.tipo_consulta,
            "codigo": request.codigo
        })

        message = Message(body=mensaje.encode(), delivery_mode=DeliveryMode.PERSISTENT)
        await app_state.rabbitmq_channel.default_exchange.publish(message, routing_key=QUEUE_NAME)

        print(f"Consulta {consulta_id} creada y encolada (tipo: {request.tipo_consulta})")

        return ConsultaCreateResponse(
            consulta_id=consulta_id,
            status="pending",
            message="Consulta encolada exitosamente"
        )

    except Exception as e:
        print(f"Error creando consulta: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@app.get("/consultar/{consulta_id}", response_model=ConsultaStatusResponse)
async def obtener_estado_consulta(consulta_id: int):
    """
    Obtiene el estado y resultado de una consulta (polling endpoint).

    Estados posibles:
    - pending: El Worker aún no ha procesado la consulta
    - completed: Consulta procesada exitosamente (resultado disponible en campo 'resultado')
    - not_found: El producto buscado no existe (solo para buscar_codigo)
    """
    try:
        async with app_state.db_pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT id, tipo_consulta, codigo_buscado, status, resultado,
                       created_at, processed_at
                FROM consulta
                WHERE id = $1
                """,
                consulta_id
            )

        if not row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Consulta {consulta_id} no encontrada"
            )

        return ConsultaStatusResponse(
            consulta_id=row["id"],
            tipo_consulta=row["tipo_consulta"],
            codigo_buscado=row["codigo_buscado"],
            status=row["status"],
            resultado=json.loads(row["resultado"]) if row["resultado"] else None,
            created_at=row["created_at"].isoformat(),
            processed_at=row["processed_at"].isoformat() if row["processed_at"] else None
        )

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error consultando estado de consulta {consulta_id}: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
