#!/usr/bin/env bash
# Espera a que un componente desplegado sirva una versión concreta.
#
# ECS reemplaza las tareas de forma gradual (rolling update): durante unos
# minutos el ALB puede responder con la versión vieja. Las pruebas solo deben
# empezar cuando el componente reporta la versión nueva.
#
#   scripts/esperar-version.sh <url-base> <backend|frontend> <version> [intentos]
#
#   backend  → GET /health   (gateway; todos los servicios comparten imagen)
#   frontend → GET /healthz  (Next.js)
set -uo pipefail

BASE="${1:?Uso: esperar-version.sh <url-base> <backend|frontend> <version> [intentos]}"
COMPONENTE="${2:?Falta el componente (backend|frontend)}"
VERSION="${3:?Falta la versión esperada}"
INTENTOS="${4:-40}"   # 40 × 15 s = 10 minutos

case "$COMPONENTE" in
  backend) RUTA=/health ;;
  frontend) RUTA=/healthz ;;
  *) echo "Componente desconocido: $COMPONENTE" >&2; exit 2 ;;
esac

for i in $(seq 1 "$INTENTOS"); do
  actual=$(curl -s --max-time 5 "$BASE$RUTA" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>/dev/null)
  echo "[$i/$INTENTOS] $COMPONENTE=${actual:-—} (esperada $VERSION)"
  if [ "$actual" = "$VERSION" ]; then
    echo "✓ $COMPONENTE sirve la versión $VERSION en $BASE"
    exit 0
  fi
  sleep 15
done

echo "::error::$COMPONENTE no llegó a la versión $VERSION en $((INTENTOS * 15)) s"
exit 1
