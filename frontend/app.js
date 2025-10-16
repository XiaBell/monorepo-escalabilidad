/**
 * Frontend Application - Sistema de Escalabilidad
 * Gestiona consultas asíncronas de productos
 */

const API_BASE_URL = 'http://localhost:8000';
const POLLING_INTERVAL = 1500;

const appState = {
    consultasPendientes: new Map(),
    pollingIntervals: new Map(),
    resultados: []
};


function showToast(message, type = 'info') {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.className = `toast ${type} show`;
    setTimeout(() => toast.classList.remove('show'), 3000);
}


async function fetchAPI(endpoint, options = {}) {
    try {
        const response = await fetch(`${API_BASE_URL}${endpoint}`, {
            headers: {'Content-Type': 'application/json', ...options.headers},
            ...options
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Error en la petición');
        }

        return await response.json();
    } catch (error) {
        console.error('Error en fetchAPI:', error);
        throw error;
    }
}


async function checkHealth() {
    try {
        const health = await fetchAPI('/health');
        updateStatusIndicator('api-status', health.api);
        updateStatusIndicator('db-status', health.database);
        updateStatusIndicator('mq-status', health.message_broker);
    } catch (error) {
        console.error('Error en health check:', error);
        updateStatusIndicator('api-status', 'unhealthy');
        updateStatusIndicator('db-status', 'unknown');
        updateStatusIndicator('mq-status', 'unknown');
    }
}


function updateStatusIndicator(elementId, status) {
    const element = document.getElementById(elementId);
    element.textContent = status;
    element.className = 'status-indicator';

    if (status === 'healthy') {
        element.classList.add('healthy');
    } else if (status.includes('unhealthy')) {
        element.classList.add('unhealthy');
    } else {
        element.classList.add('checking');
    }
}


async function crearConsulta(tipoConsulta, codigo = null) {
    try {
        const body = {tipo_consulta: tipoConsulta};
        if (codigo) body.codigo = codigo;

        const response = await fetchAPI('/consultar', {
            method: 'POST',
            body: JSON.stringify(body)
        });

        showToast(`Consulta ${response.consulta_id} creada`, 'success');

        appState.consultasPendientes.set(response.consulta_id, {
            consulta_id: response.consulta_id,
            tipo_consulta: tipoConsulta,
            codigo: codigo,
            status: 'pending',
            created_at: new Date().toISOString()
        });

        renderConsultasPendientes();
        startPolling(response.consulta_id);

    } catch (error) {
        showToast(`Error: ${error.message}`, 'error');
    }
}


async function startPolling(consultaId) {
    const intervalId = setInterval(async () => {
        await pollConsulta(consultaId);
    }, POLLING_INTERVAL);

    appState.pollingIntervals.set(consultaId, intervalId);
}


async function pollConsulta(consultaId) {
    try {
        const consulta = await fetchAPI(`/consultar/${consultaId}`);

        appState.consultasPendientes.set(consultaId, consulta);

        if (consulta.status === 'completed' || consulta.status === 'not_found') {
            stopPolling(consultaId);
            moveToResultados(consulta);
        }

        renderConsultasPendientes();

    } catch (error) {
        console.error(`Error polling consulta ${consultaId}:`, error);
        stopPolling(consultaId);
    }
}


function stopPolling(consultaId) {
    const intervalId = appState.pollingIntervals.get(consultaId);
    if (intervalId) {
        clearInterval(intervalId);
        appState.pollingIntervals.delete(consultaId);
    }
}


function moveToResultados(consulta) {
    appState.consultasPendientes.delete(consulta.consulta_id);
    appState.resultados.unshift(consulta);

    if (appState.resultados.length > 5) {
        appState.resultados = appState.resultados.slice(0, 5);
    }

    renderConsultasPendientes();
    renderResultados();

    if (consulta.status === 'completed') {
        showToast(`Consulta ${consulta.consulta_id} completada`, 'success');
    } else {
        showToast(`Consulta ${consulta.consulta_id}: Producto no encontrado`, 'error');
    }
}


function renderConsultasPendientes() {
    const container = document.getElementById('consultas-pendientes');

    if (appState.consultasPendientes.size === 0) {
        container.innerHTML = '<p class="empty-state">No hay consultas en proceso</p>';
        return;
    }

    const html = Array.from(appState.consultasPendientes.values())
        .map(consulta => `
            <div class="consulta-item">
                <div class="consulta-header">
                    <span class="consulta-id">Consulta #${consulta.consulta_id}</span>
                    <span class="consulta-status ${consulta.status}">${consulta.status}</span>
                </div>
                <div class="consulta-body">
                    <p><strong>Tipo:</strong> ${consulta.tipo_consulta}</p>
                    ${consulta.codigo ? `<p><strong>Código:</strong> ${consulta.codigo}</p>` : ''}
                    <div class="loading-spinner"></div>
                </div>
            </div>
        `)
        .join('');

    container.innerHTML = html;
}


function renderResultados() {
    const container = document.getElementById('resultados');

    if (appState.resultados.length === 0) {
        container.innerHTML = '<p class="empty-state">No hay resultados disponibles</p>';
        return;
    }

    const html = appState.resultados.map(consulta => {
        let resultadoHtml = '';

        if (consulta.status === 'completed' && consulta.resultado) {
            if (Array.isArray(consulta.resultado)) {
                resultadoHtml = `
                    <div class="productos-grid">
                        ${consulta.resultado.map(producto => `
                            <div class="producto-card">
                                <div class="producto-codigo">${producto.codigo}</div>
                                <div class="producto-nombre">${producto.nombre}</div>
                                <div class="producto-ubicacion">${producto.ubicacion}</div>
                            </div>
                        `).join('')}
                    </div>
                `;
            } else {
                resultadoHtml = `
                    <div class="producto-card destacado">
                        <div class="producto-codigo">${consulta.resultado.codigo}</div>
                        <div class="producto-nombre">${consulta.resultado.nombre}</div>
                        <div class="producto-ubicacion">${consulta.resultado.ubicacion}</div>
                    </div>
                `;
            }
        } else if (consulta.status === 'not_found') {
            resultadoHtml = `
                <div class="error-box">
                    Producto con código "${consulta.codigo_buscado}" no encontrado
                </div>
            `;
        }

        return `
            <div class="resultado-item">
                <div class="resultado-header">
                    <span class="consulta-id">Consulta #${consulta.consulta_id}</span>
                    <span class="consulta-status ${consulta.status}">${consulta.status}</span>
                </div>
                <div class="resultado-body">
                    ${resultadoHtml}
                </div>
            </div>
        `;
    }).join('');

    container.innerHTML = html;
}


function initializeApp() {
    console.log('Inicializando aplicación...');

    document.getElementById('btn-listar-todos').addEventListener('click', () => {
        crearConsulta('listar_todos');
    });

    document.getElementById('btn-buscar-codigo').addEventListener('click', () => {
        const codigo = document.getElementById('input-codigo').value.trim();
        if (!codigo) {
            showToast('Por favor ingresa un código', 'error');
            return;
        }
        crearConsulta('buscar_codigo', codigo);
        document.getElementById('input-codigo').value = '';
    });

    document.getElementById('input-codigo').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            document.getElementById('btn-buscar-codigo').click();
        }
    });

    checkHealth();
    setInterval(checkHealth, 10000);

    console.log('Aplicación inicializada');
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeApp);
} else {
    initializeApp();
}
