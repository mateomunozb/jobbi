"""Configuración compartida de las pruebas contra un ambiente desplegado.

Las pruebas de tests/e2e (pre-prod, staging) y tests/smoke (post-prod) no
importan código del backend: hablan HTTP con el ALB del ambiente, igual que un
usuario. El pipeline les pasa la URL y la versión esperada de cada componente
(backend y frontend se despliegan por separado, cada uno con su versión):

    APP_BASE_URL=http://jobbi-staging-alb-123.us-east-1.elb.amazonaws.com \
    EXPECTED_BACKEND_VERSION=<tag> EXPECTED_FRONTEND_VERSION=<tag> \
    python -m pytest tests/smoke -v
"""

from __future__ import annotations

import os

import pytest
import requests

TIMEOUT = 15


class Cliente:
    """Cliente HTTP mínimo contra el ALB, con la URL base ya aplicada."""

    def __init__(self, base: str):
        self.base = base.rstrip("/")
        self.sesion = requests.Session()

    def get(self, ruta: str, **kw):
        return self.sesion.get(self.base + ruta, timeout=TIMEOUT, **kw)

    def post(self, ruta: str, cuerpo: dict | None = None, **kw):
        return self.sesion.post(self.base + ruta, json=cuerpo or {}, timeout=TIMEOUT, **kw)


@pytest.fixture(scope="session")
def base_url() -> str:
    url = os.getenv("APP_BASE_URL")
    if not url:
        pytest.skip("APP_BASE_URL no definida: estas pruebas corren contra un ambiente desplegado")
    return url


@pytest.fixture(scope="session")
def api(base_url) -> Cliente:
    return Cliente(base_url)


@pytest.fixture(scope="session")
def version_backend() -> str | None:
    """Versión que debe reportar el gateway en /health (None: no se verifica)."""
    return os.getenv("EXPECTED_BACKEND_VERSION") or None


@pytest.fixture(scope="session")
def version_frontend() -> str | None:
    """Versión que debe reportar el frontend en /healthz (None: no se verifica)."""
    return os.getenv("EXPECTED_FRONTEND_VERSION") or None
