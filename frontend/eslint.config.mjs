// Análisis estático del frontend (job "static-analysis" del pipeline de CI).
import nextVitals from "eslint-config-next/core-web-vitals"
import nextTs from "eslint-config-next/typescript"

const config = [
  ...nextVitals,
  ...nextTs,
  { ignores: [".next/**", "node_modules/**", "next-env.d.ts", "public/**"] },
  {
    // Deuda técnica conocida: se reporta como advertencia (visible en el log del
    // pipeline y en Sonar) sin bloquear el build. Cualquier otra regla bloquea.
    rules: {
      "@typescript-eslint/no-explicit-any": "warn",
      "react-hooks/set-state-in-effect": "warn",
      "react-hooks/refs": "warn",
    },
  },
]

export default config
