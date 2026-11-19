// Health check del frontend para el target group del ALB y las pruebas smoke.
// No toca el gateway: un backend caído no debe sacar al frontend del balanceador.
export const dynamic = "force-dynamic"

export function GET() {
  return Response.json({
    status: "UP",
    service: "frontend",
    version: process.env.APP_VERSION ?? "local",
  })
}
