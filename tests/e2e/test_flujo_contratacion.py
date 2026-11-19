"""Pruebas de aceptación end-to-end en staging (pre-prod).

Recorren el flujo de negocio completo a través del ALB, con la infraestructura
real del ambiente (ECS, RDS, SNS, SQS):

    registro → verificación (RN-01) → oferta → contacto + chat → acuerdo de
    tarifa → check-in → check-out → evento por Outbox → SNS → SQS →
    Monetización cobra la comisión en la billetera del prestador

Si todo pasa, la versión es candidata a producción.
"""

from __future__ import annotations

import time
import uuid

import pytest

SUFIJO = uuid.uuid4().hex[:10]


def _registrar(api, rol: str, nombre: str) -> dict:
    """Registra un usuario cuyo documento pase la verificación de antecedentes.

    El aliado de verificación (doble de prueba) rechaza un porcentaje de
    documentos de forma determinista; se prueba con varios hasta uno aprobado.
    """
    clave = "perfilPrestador" if rol == "Prestador" else "perfilDemandante"
    base_documento = 10_000_000 + int(SUFIJO[:6], 16) % 80_000_000
    for intento in range(8):
        cuerpo = {
            "nombreCompleto": f"E2E {nombre}",
            "correo": f"e2e.{nombre.lower()}.{SUFIJO}.{intento}@example.com",
            "telefono": "3001112222",
            "numeroDocumento": str(base_documento + intento),
            "rol": rol,
        }
        if rol == "Prestador":
            cuerpo |= {"descripcion": "Prestador de prueba E2E", "tarifaReferencialBase": 90000}
        respuesta = api.post("/api/auth/registro", cuerpo)
        assert respuesta.status_code == 201, respuesta.text
        sesion = respuesta.json()
        if sesion[clave].get("estadoVerificacionActual") == "APROBADA":
            return sesion
    pytest.fail(f"Ningún documento de {rol} quedó APROBADO: revisar Confianza y el aliado de verificación")


@pytest.fixture(scope="module")
def escenario(api):
    prestador = _registrar(api, "Prestador", "Prestador")
    demandante = _registrar(api, "Demandante", "Demandante")
    return {
        "prestador": prestador["perfilPrestador"]["id"],
        "demandante": demandante["perfilDemandante"]["id"],
        "usuario_demandante": demandante["usuario"]["id"],
        "correo_prestador": prestador["usuario"]["correo"],
    }


def test_login_con_el_correo_registrado(api, escenario):
    respuesta = api.post("/api/auth/login", {"correo": escenario["correo_prestador"]})
    assert respuesta.status_code == 200


def test_login_con_correo_inexistente_es_rechazado(api):
    assert api.post("/api/auth/login", {"correo": f"nadie.{SUFIJO}@example.com"}).status_code == 404


def test_registro_con_datos_invalidos_es_rechazado(api):
    respuesta = api.post("/api/auth/registro", {"nombreCompleto": "X", "correo": "no-es-correo", "rol": "Demandante"})
    assert respuesta.status_code in (400, 422)


def test_flujo_completo_de_contratacion_con_cobro_por_eventos(api, escenario):
    prestador, demandante = escenario["prestador"], escenario["demandante"]

    # Oferta del prestador en el catálogo (Mercado)
    oficio = api.post("/api/mercado/catalogo/oficio", {
        "categoriaNombre": "Hogar", "oficioNombre": f"Plomería E2E {SUFIJO}"})
    assert oficio.status_code == 201, oficio.text
    oficio_id = oficio.json()["oficio"]["id"]
    oferta = api.post("/api/mercado/prestador-oficios", {
        "prestadorId": prestador, "oficioId": oficio_id, "tarifaReferencial": 90000, "anosExperiencia": 5})
    assert oferta.status_code == 201, oferta.text

    # Contactar: abre contacto (Mercado) y conversación (Comunicación)
    contacto = api.post("/api/bff/contactar", {"demandanteId": demandante, "prestadorId": prestador})
    assert contacto.status_code == 201, contacto.text
    contacto_id = contacto.json()["contacto"]["id"]
    conversacion_id = contacto.json()["conversacion"]["id"]

    mensaje = api.post("/api/comunicacion/mensajes", {
        "conversacionId": conversacion_id, "remitenteId": escenario["usuario_demandante"],
        "contenido": "Hola, ¿puedes venir mañana?"})
    assert mensaje.status_code == 201, mensaje.text

    # Acuerdo de tarifa: el demandante propone y el prestador acepta
    propuesta = api.post("/api/bff/acuerdos", {
        "contactoId": contacto_id, "conversacionId": conversacion_id,
        "demandanteId": demandante, "prestadorId": prestador,
        "oficioId": oficio_id, "valorPropuesto": 100000, "propuestoPor": "DEMANDANTE"})
    assert propuesta.status_code == 201, propuesta.text
    acuerdo_id = propuesta.json()["acuerdo"]["id"]

    aceptado = api.post(f"/api/bff/acuerdos/{acuerdo_id}/aceptar", {"rol": "PRESTADOR"})
    assert aceptado.status_code == 200, aceptado.text
    contratacion = aceptado.json()["contratacion"]
    assert contratacion, "Al aceptar debía nacer la contratación"
    contratacion_id = contratacion["id"]

    # Ejecución del servicio
    assert api.post(f"/api/bff/contrataciones/{contratacion_id}/check-in").status_code == 200
    cierre = api.post(f"/api/bff/contrataciones/{contratacion_id}/check-out")
    assert cierre.status_code == 200, cierre.text
    comision = cierre.json()["contratacion"]["montoComision"]
    assert comision > 0

    # Cobro asíncrono: Outbox → SNS → SQS → Monetización (infraestructura real)
    etapa = None
    for _ in range(30):
        etapa = api.get(f"/api/bff/contrataciones/{contratacion_id}/cobro").json()["etapa"]
        if etapa == "COBRADO":
            break
        time.sleep(3)
    assert etapa == "COBRADO", f"El cobro no llegó por eventos (última etapa: {etapa})"

    billetera = api.get("/api/monetizacion/billeteras", params={"prestadorId": prestador}).json()
    assert billetera["items"][0]["saldoPendiente"] >= comision


def test_ficha_360_del_prestador_por_bff(api, escenario):
    assert api.get(f"/api/bff/prestadores/{escenario['prestador']}").status_code == 200


def test_contexto_no_desplegado_responde_error_controlado(api):
    """Soporte no se despliega en AWS: el gateway responde 5xx controlado, sin colgarse."""
    assert api.get("/api/soporte/incidentes").status_code in (502, 503, 504)
