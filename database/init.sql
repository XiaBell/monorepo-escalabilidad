-- Inicialización de la base de datos
-- PostgreSQL 17

-- Tabla de productos (solo accesible por el Worker)
CREATE TABLE IF NOT EXISTS producto (
    codigo VARCHAR(50) PRIMARY KEY,
    nombre VARCHAR(200) NOT NULL,
    ubicacion VARCHAR(200) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_producto_nombre ON producto(nombre);

-- Datos de prueba
INSERT INTO producto (codigo, nombre, ubicacion) VALUES
    ('PROD001', 'Laptop Dell XPS 15', 'Almacén A - Estante 1'),
    ('PROD002', 'Mouse Logitech MX Master', 'Almacén A - Estante 2'),
    ('PROD003', 'Teclado Mecánico Corsair', 'Almacén B - Estante 1'),
    ('PROD004', 'Monitor LG 27 pulgadas', 'Almacén B - Estante 3'),
    ('PROD005', 'Auriculares Sony WH-1000XM4', 'Almacén A - Estante 5'),
    ('PROD006', 'Webcam Logitech C920', 'Almacén B - Estante 2'),
    ('PROD007', 'SSD Samsung 1TB', 'Almacén A - Estante 3'),
    ('PROD008', 'Router TP-Link AX6000', 'Almacén B - Estante 5')
ON CONFLICT (codigo) DO NOTHING;

-- Tabla de consultas (casillero para resultados)
-- API Gateway crea registros y lee estado/resultado
-- Worker actualiza el resultado y cambia el estado
CREATE TABLE IF NOT EXISTS consulta (
    id SERIAL PRIMARY KEY,
    codigo_buscado VARCHAR(50),
    tipo_consulta VARCHAR(20) NOT NULL DEFAULT 'buscar_codigo',
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    resultado JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT valid_status CHECK (status IN ('pending', 'completed', 'not_found')),
    CONSTRAINT valid_tipo CHECK (tipo_consulta IN ('listar_todos', 'buscar_codigo'))
);

CREATE INDEX idx_consulta_status ON consulta(status);
CREATE INDEX idx_consulta_created ON consulta(created_at DESC);

COMMENT ON TABLE producto IS 'Tabla de productos - Solo accesible por Worker';
COMMENT ON TABLE consulta IS 'Tabla de consultas - API Gateway crea y lee, Worker actualiza';
