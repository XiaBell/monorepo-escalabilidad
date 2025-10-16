"""
DTOs para el API Gateway
Modelos Pydantic para validación y serialización
"""

from typing import Optional, Any
from pydantic import BaseModel, Field


class ConsultaRequest(BaseModel):
    """Request para crear una consulta"""
    tipo_consulta: str = Field(..., description="Tipo: 'listar_todos' o 'buscar_codigo'")
    codigo: Optional[str] = Field(None, description="Código del producto (solo para buscar_codigo)")

    class Config:
        json_schema_extra = {
            "examples": [
                {
                    "tipo_consulta": "listar_todos",
                    "codigo": None
                },
                {
                    "tipo_consulta": "buscar_codigo",
                    "codigo": "PROD001"
                }
            ]
        }


class ConsultaCreateResponse(BaseModel):
    """Respuesta al crear una consulta"""
    consulta_id: int
    status: str
    message: str


class ConsultaStatusResponse(BaseModel):
    """Respuesta al consultar el estado de una consulta"""
    consulta_id: int
    tipo_consulta: str
    codigo_buscado: Optional[str] = None
    status: str
    resultado: Optional[Any] = None
    created_at: str
    processed_at: Optional[str] = None
