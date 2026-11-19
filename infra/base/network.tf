# Grupos de seguridad: cada capa solo acepta tráfico de la capa anterior y
# solo sale hacia donde lo necesita (mínimo privilegio en red).
#   Internet :80 → ALB → tareas (3000 frontend, 8080 gateway)
#   tareas ↔ tareas (Service Connect entre contextos)
#   tareas → RDS :5432 · tareas → APIs de AWS :443 (ECR, SSM, SNS, SQS, Logs)
#
# Las reglas van como recursos separados (aws_vpc_security_group_*_rule) para
# poder referenciar un grupo desde otro sin dependencias circulares.

locals {
  # Puertos que el ALB alcanza en las tareas: frontend (Next.js) y gateway.
  puertos_alb_a_tareas = { frontend = 3000, gateway = 8080 }
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB publico de JOBBI"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "Tareas ECS de JOBBI"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "PostgreSQL de JOBBI, solo desde las tareas"
  vpc_id      = data.aws_vpc.default.id
}

# --- ALB ---------------------------------------------------------------------

# Única entrada pública. HTTP porque el Learner Lab no tiene dominio propio
# para emitir un certificado en ACM (riesgo aceptado y documentado).
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP publico"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_a_tareas" {
  for_each = local.puertos_alb_a_tareas

  security_group_id            = aws_security_group.alb.id
  description                  = "ALB hacia ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = aws_security_group.ecs.id
}

# --- Tareas ECS --------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "tareas_desde_alb" {
  for_each = local.puertos_alb_a_tareas

  security_group_id            = aws_security_group.ecs.id
  description                  = "${each.key} desde el ALB"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "tareas_entre_si" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Trafico entre servicios (Service Connect)"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "tareas_entre_si" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Trafico entre servicios (Service Connect)"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "tareas_a_rds" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

# Sin NAT ni VPC endpoints (costo en el Learner Lab), las APIs de AWS se
# alcanzan por sus endpoints públicos: solo HTTPS.
resource "aws_vpc_security_group_egress_rule" "tareas_a_aws" {
  security_group_id = aws_security_group.ecs.id
  description       = "APIs de AWS por HTTPS (ECR, SSM, SNS, SQS, CloudWatch)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# --- RDS ---------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rds_desde_tareas" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL desde ECS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ecs.id
}
