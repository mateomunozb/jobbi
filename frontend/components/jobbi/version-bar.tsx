"use client"

import { useEffect, useState } from "react"

type Versiones = { ambiente: string; backend: string; frontend: string }

// Pie de página con el ambiente y la versión desplegada de cada componente.
// Frontend: /healthz (sirve este mismo contenedor). Backend: /api/version del
// gateway, por el proxy /api. Si alguno no responde se muestra "—".
export function VersionBar() {
  const [v, setV] = useState<Versiones | null>(null)

  useEffect(() => {
    const leer = (url: string) =>
      fetch(url, { cache: "no-store" })
        .then((r) => (r.ok ? r.json() : null))
        .catch(() => null)

    // `leer` nunca rechaza (atrapa sus errores), así que no hace falta .catch.
    void Promise.all([leer("/healthz"), leer("/api/version")]).then(([front, back]) =>
      setV({
        ambiente: back?.ambiente ?? "—",
        backend: back?.backend ?? "—",
        frontend: front?.version ?? "—",
      }),
    )
  }, [])

  if (!v) return null
  return (
    <footer className="version-bar" aria-label="Versión desplegada">
      <span className="version-ambiente">{v.ambiente}</span>
      <span>backend {v.backend}</span>
      <span>frontend {v.frontend}</span>
    </footer>
  )
}
