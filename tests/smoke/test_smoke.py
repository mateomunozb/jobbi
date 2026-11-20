"""Pruebas de humo post-despliegue (producción).

Son rápidas, no crean datos y responden una sola pregunta: ¿el ambiente que
acaba de desplegarse está vivo, con la versión correcta y sus contextos
conectados? Si alguna falla, el pipeline ejecuta el rollback automático.
"""

from __future__ import annotations


def test_frontend_responde_con_la_version_desplegada(api, version_frontend):
    salud = api.get("/healthz")
    assert salud.status_code == 200
    assert salud.json()["status"] == "UP"
    if version_frontend:
        assert salud.json()["version"] == version_frontend


def test_pagina_principal_del_frontend(api):
    pagina = api.get("/")
    assert pagina.status_code == 200
    assert "text/html" in pagina.headers.get("content-type", "")


def test_gateway_responde_con_la_version_desplegada(api, version_backend):
    salud = api.get("/health")
    assert salud.status_code == 200
    cuerpo = salud.json()
    assert cuerpo["status"] == "UP"
    assert cuerpo["service"] == "gateway"
    if version_backend:
        assert cuerpo["version"] == version_backend


def test_version_visible_en_la_interfaz(api, version_backend):
    """El pie de página de la app lee /api/version: ambiente y versión reales."""
    cuerpo = api.get("/api/version").json()
    assert cuerpo["ambiente"]
    if version_backend:
        assert cuerpo["backend"] == version_backend


def test_todos_los_contextos_desplegados_estan_arriba(api):
    """El gateway sondea cada servicio por Service Connect: valida la red interna."""
    estado = api.get("/health/servicios").json()
    caidos = [s["servicio"] for s in estado["servicios"] if s["status"] != "UP"]
    assert not caidos, f"Contextos caídos: {caidos}"
    assert estado["totalServicios"] >= 6


def test_lectura_de_datos_por_el_gateway(api):
    """Una lectura real que cruza ALB → gateway → servicio → RDS."""
    respuesta = api.get("/api/mercado/categorias")
    assert respuesta.status_code == 200
    assert isinstance(respuesta.json(), list)


def test_catalogo_bff(api):
    assert api.get("/api/bff/catalogo").status_code == 200
