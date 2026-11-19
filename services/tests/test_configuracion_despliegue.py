"""Configuración que cambia entre Minikube (LocalStack) y AWS real (ECS).

La misma imagen corre en los dos lados; lo que cambia son variables de entorno.
Estas pruebas fijan ese contrato para que el pipeline de CD no descubra en
staging que un servicio quedó apuntando a LocalStack o con credenciales falsas.

    cd services && python -m pytest -v tests/test_configuracion_despliegue.py
"""

from __future__ import annotations

import importlib

import pytest
from fastapi.testclient import TestClient


def _recargar(modulo: str, monkeypatch, **entorno):
    for clave, valor in entorno.items():
        if valor is None:
            monkeypatch.delenv(clave, raising=False)
        else:
            monkeypatch.setenv(clave, valor)
    return importlib.reload(importlib.import_module(modulo))


@pytest.fixture
def restaurar_eventos():
    yield
    import common.eventos

    importlib.reload(common.eventos)


def test_localstack_por_defecto_usa_endpoint_y_credenciales_de_prueba(monkeypatch, restaurar_eventos):
    eventos = _recargar(
        "common.eventos", monkeypatch,
        AWS_PROVEEDOR=None, AWS_ENDPOINT_URL=None, AWS_ACCESS_KEY_ID=None, AWS_SECRET_ACCESS_KEY=None,
    )
    opciones = eventos.opciones_cliente()
    assert opciones["endpoint_url"] == "http://localstack.aws-local.svc.cluster.local:4566"
    assert opciones["aws_access_key_id"] == "test"


def test_aws_real_no_fija_endpoint_ni_credenciales(monkeypatch, restaurar_eventos):
    """En ECS boto3 debe tomar el rol de la tarea (LabRole), no llaves fijas.

    La task definition no define AWS_ENDPOINT_URL: boto3 también la lee por su
    cuenta y desviaría el tráfico aunque el código no la pase.
    """
    eventos = _recargar(
        "common.eventos", monkeypatch,
        AWS_PROVEEDOR="aws", AWS_ENDPOINT_URL=None, AWS_REGION="us-east-1",
    )
    assert eventos.AWS_ENDPOINT_URL is None
    assert eventos.opciones_cliente() == {"region_name": "us-east-1"}
    # Crear el cliente no debe exigir credenciales ni endpoint.
    assert eventos.cliente("sns").meta.endpoint_url.startswith("https://sns.us-east-1")


@pytest.fixture
def restaurar_registro():
    yield
    import gateway.registro

    importlib.reload(gateway.registro)


def test_registro_sin_filtro_considera_activos_todos_los_contextos(monkeypatch, restaurar_registro):
    registro = _recargar("gateway.registro", monkeypatch, SERVICIOS_ACTIVOS=None)
    assert registro.ACTIVOS == list(registro.SERVICIOS)


def test_registro_filtra_los_contextos_desplegados_y_respeta_urls(monkeypatch, restaurar_registro):
    registro = _recargar(
        "gateway.registro", monkeypatch,
        SERVICIOS_ACTIVOS="identidad, monetizacion,desconocido",
        SERVICIO_IDENTIDAD_URL="http://identidad:8001",
    )
    assert registro.ACTIVOS == ["identidad", "monetizacion"]
    # Los no desplegados siguen registrados: sus rutas responden 502, no 500.
    assert "soporte" in registro.SERVICIOS
    assert registro.SERVICIOS["identidad"]["url"] == "http://identidad:8001"


def test_health_servicios_solo_sondea_los_activos(monkeypatch):
    from gateway import main as gateway

    sondeados = []

    async def _pedir(servicio, ruta, params=None):
        sondeados.append(servicio)
        return {"status": "UP"}

    monkeypatch.setattr(gateway, "_pedir", _pedir)
    monkeypatch.setattr(gateway, "ACTIVOS", ["identidad", "mercado"])
    with TestClient(gateway.app) as api:
        cuerpo = api.get("/health/servicios").json()

    assert sorted(sondeados) == ["identidad", "mercado"]
    assert cuerpo["status"] == "UP"
    assert cuerpo["totalServicios"] == 2


def test_health_reporta_la_version_desplegada(monkeypatch):
    service = _recargar("common.service", monkeypatch, APP_VERSION="abc123")
    try:
        app = service.crear_servicio(nombre="prueba", contexto="Prueba", descripcion="-")
        with TestClient(app) as api:
            assert api.get("/health").json()["version"] == "abc123"
    finally:
        monkeypatch.delenv("APP_VERSION")
        importlib.reload(service)


def test_crear_base_si_falta_no_actua_sin_bandera_ni_fuera_de_postgres(monkeypatch):
    from sqlalchemy import create_engine

    from common.db import crear_base_si_falta

    sqlite = create_engine("sqlite://")
    postgres = create_engine("postgresql+psycopg://u:p@127.0.0.1:1/jobbi_identidad")

    monkeypatch.delenv("CREAR_BASE_SI_FALTA", raising=False)
    assert crear_base_si_falta(postgres) is False
    monkeypatch.setenv("CREAR_BASE_SI_FALTA", "true")
    assert crear_base_si_falta(sqlite) is False


def test_crear_base_si_falta_rechaza_nombres_no_seguros(monkeypatch):
    from sqlalchemy import create_engine

    from common.db import crear_base_si_falta

    monkeypatch.setenv("CREAR_BASE_SI_FALTA", "true")
    with pytest.raises(ValueError):
        crear_base_si_falta(create_engine('postgresql+psycopg://u:p@127.0.0.1:1/x";DROP'))


def test_crear_base_si_falta_tolera_servidor_caido(monkeypatch):
    """Si RDS aún no acepta conexiones, no falla: esperar_a_la_base reintenta."""
    from sqlalchemy import create_engine

    from common.db import crear_base_si_falta

    monkeypatch.setenv("CREAR_BASE_SI_FALTA", "true")
    caido = create_engine("postgresql+psycopg://u:p@127.0.0.1:1/jobbi_mercado?connect_timeout=1")
    assert crear_base_si_falta(caido) is False
