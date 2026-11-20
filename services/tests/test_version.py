"""El gateway expone el ambiente y la versión desplegada para el pie de página.

    cd services && python -m pytest -v tests/test_version.py
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from common.service import VERSION
from gateway import main as gateway


def test_version_reporta_ambiente_y_version_del_backend(monkeypatch):
    monkeypatch.setattr(gateway, "AMBIENTE", "staging")
    with TestClient(gateway.app) as cliente:
        respuesta = cliente.get("/api/version")
    assert respuesta.status_code == 200
    assert respuesta.json() == {"ambiente": "staging", "backend": VERSION}


def test_version_no_se_confunde_con_el_proxy():
    """/api/version es del gateway; no se reenvía a un servicio llamado 'version'."""
    rutas = [r.path for r in gateway.app.routes]
    assert rutas.index("/api/version") < rutas.index("/api/{servicio}/{ruta:path}")
