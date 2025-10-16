"""
Worker Service - Sistema de Escalabilidad
Responsabilidad: Procesar consultas consumiendo de RabbitMQ
- Lee de la tabla 'producto' (es el ÚNICO que puede hacerlo)
- Actualiza la tabla 'consulta' con los resultados
"""

import os
import json
import asyncio
from datetime import datetime

import asyncpg
from aio_pika import connect_robust, IncomingMessage
from aio_pika.abc import AbstractRobustConnection


DATABASE_URL = os.getenv("DATABASE_URL")
RABBITMQ_URL = os.getenv("RABBITMQ_URL")
QUEUE_NAME = os.getenv("QUEUE_NAME", "consulta_queue")
WORKER_ID = os.getenv("HOSTNAME", "worker-1")


class ProductoWorker:
    """Worker que procesa consultas de productos"""

    def __init__(self):
        self.db_pool: asyncpg.Pool = None
        self.rabbitmq_connection: AbstractRobustConnection = None
        self.worker_id = WORKER_ID
        self.is_running = True

    async def initialize(self):
        """Inicializa conexiones a PostgreSQL y RabbitMQ"""
        print(f"Inicializando Worker '{self.worker_id}'...")

        try:
            self.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=10)
            print("Conexión a PostgreSQL establecida")
        except Exception as e:
            print(f"Error conectando a PostgreSQL: {e}")
            raise

        try:
            self.rabbitmq_connection = await connect_robust(RABBITMQ_URL)
            print("Conexión a RabbitMQ establecida")
        except Exception as e:
            print(f"Error conectando a RabbitMQ: {e}")
            raise

        print(f"Worker '{self.worker_id}' listo\n")

    async def procesar_consulta(self, consulta_id: int, tipo_consulta: str, codigo: str = None):
        """
        Procesa una consulta según su tipo:
        - listar_todos: Retorna todos los productos
        - buscar_codigo: Busca un producto específico por código
        """
        print(f"[{self.worker_id}] Procesando consulta {consulta_id} (tipo: {tipo_consulta})")

        try:
            async with self.db_pool.acquire() as conn:
                if tipo_consulta == "listar_todos":
                    rows = await conn.fetch(
                        "SELECT codigo, nombre, ubicacion FROM producto ORDER BY codigo"
                    )

                    if rows:
                        resultado = [
                            {
                                "codigo": row["codigo"],
                                "nombre": row["nombre"],
                                "ubicacion": row["ubicacion"]
                            }
                            for row in rows
                        ]
                        await self.actualizar_consulta(
                            conn, consulta_id, "completed", resultado
                        )
                        print(f"[{self.worker_id}] Consulta {consulta_id}: {len(resultado)} productos encontrados")
                    else:
                        await self.actualizar_consulta(
                            conn, consulta_id, "completed", []
                        )
                        print(f"[{self.worker_id}] Consulta {consulta_id}: No hay productos")

                elif tipo_consulta == "buscar_codigo":
                    row = await conn.fetchrow(
                        "SELECT codigo, nombre, ubicacion FROM producto WHERE codigo = $1",
                        codigo
                    )

                    if row:
                        resultado = {
                            "codigo": row["codigo"],
                            "nombre": row["nombre"],
                            "ubicacion": row["ubicacion"]
                        }
                        await self.actualizar_consulta(
                            conn, consulta_id, "completed", resultado
                        )
                        print(f"[{self.worker_id}] Consulta {consulta_id}: Producto '{codigo}' encontrado")
                    else:
                        await self.actualizar_consulta(
                            conn, consulta_id, "not_found", None
                        )
                        print(f"[{self.worker_id}] Consulta {consulta_id}: Producto '{codigo}' no encontrado")

        except Exception as e:
            print(f"[{self.worker_id}] Error procesando consulta {consulta_id}: {e}")
            async with self.db_pool.acquire() as conn:
                await self.actualizar_consulta(
                    conn, consulta_id, "not_found", {"error": str(e)}
                )

    async def actualizar_consulta(self, conn, consulta_id: int, status: str, resultado):
        """Actualiza el estado y resultado de una consulta en la base de datos"""
        await conn.execute(
            """
            UPDATE consulta
            SET status = $1, resultado = $2, processed_at = CURRENT_TIMESTAMP
            WHERE id = $3
            """,
            status,
            json.dumps(resultado) if resultado is not None else None,
            consulta_id
        )

    async def on_message(self, message: IncomingMessage):
        """Callback ejecutado al recibir un mensaje de RabbitMQ"""
        async with message.process():
            try:
                body = message.body.decode()
                data = json.loads(body)

                consulta_id = data.get("consulta_id")
                tipo_consulta = data.get("tipo_consulta")
                codigo = data.get("codigo")

                print(f"[{self.worker_id}] Mensaje recibido: consulta_id={consulta_id}")

                asyncio.create_task(
                    self.procesar_consulta(consulta_id, tipo_consulta, codigo)
                )

            except json.JSONDecodeError as e:
                print(f"[{self.worker_id}] Error decodificando mensaje JSON: {e}")
            except Exception as e:
                print(f"[{self.worker_id}] Error procesando mensaje: {e}")

    async def start_consuming(self):
        """Inicia el consumo de mensajes desde RabbitMQ"""
        channel = await self.rabbitmq_connection.channel()
        await channel.set_qos(prefetch_count=1)

        queue = await channel.declare_queue(QUEUE_NAME, durable=True)

        print(f"[{self.worker_id}] Esperando mensajes en cola '{QUEUE_NAME}'...\n")

        await queue.consume(self.on_message)

    async def shutdown(self):
        """Cierra las conexiones"""
        print(f"\n[{self.worker_id}] Cerrando conexiones...")
        self.is_running = False

        if self.rabbitmq_connection:
            await self.rabbitmq_connection.close()
        if self.db_pool:
            await self.db_pool.close()

        print(f"[{self.worker_id}] Conexiones cerradas")

    async def run(self):
        """Ejecuta el worker"""
        try:
            await self.initialize()
            await self.start_consuming()

            while self.is_running:
                await asyncio.sleep(1)

        except KeyboardInterrupt:
            print(f"\n[{self.worker_id}] Interrupción manual detectada")
        except Exception as e:
            print(f"\n[{self.worker_id}] Error fatal: {e}")
        finally:
            await self.shutdown()


async def main():
    """Función principal del worker"""
    worker = ProductoWorker()
    await worker.run()


if __name__ == "__main__":
    print("=" * 60)
    print("WORKER SERVICE - SISTEMA DE ESCALABILIDAD")
    print("=" * 60)
    asyncio.run(main())
