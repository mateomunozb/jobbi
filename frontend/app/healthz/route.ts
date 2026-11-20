// Health check del frontend para el target group del ALB y las pruebas smoke.
// No toca el gateway: un backend caído no debe sacar al frontend del balanceador.
export const dynamic = "force-dynamic"

// DEMO DE ROLLBACK AUTOMÁTICO (falla simulada, se revierte con otro PR).
// Solo en AWS (el gateway está detrás de un ALB *.elb.amazonaws.com) este
// health check responde 503. En el CI (docker compose, http://gateway:8080)
// sigue respondiendo 200, así que el PR pasa y la falla aparece al desplegar:
// las tareas nuevas no quedan sanas, ECS las revierte (circuit breaker), el
// job deploy-frontend falla y el pipeline ejecuta el rollback del frontend.
const fallaSimuladaEnAws = () => (process.env.API_GATEWAY_URL ?? "").includes(".elb.amazonaws.com")

export function GET() {
  if (fallaSimuladaEnAws()) {
    return Response.json({ status: "DOWN", service: "frontend", motivo: "falla simulada (demo de rollback)" }, { status: 503 })
  }
  return Response.json({
    status: "UP",
    service: "frontend",
    version: process.env.APP_VERSION ?? "local",
  })
}
