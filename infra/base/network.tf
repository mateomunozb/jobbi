# Grupos de seguridad: cada capa solo acepta tráfico de la capa anterior.
#   Internet :80 → ALB → tareas (3000 frontend, 8080 gateway)
#   tareas ↔ tareas (Service Connect entre contextos)
#   tareas → RDS :5432

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB publico de JOBBI"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP publico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "Tareas ECS de JOBBI"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Frontend y gateway desde el ALB"
    from_port       = 3000
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Trafico entre servicios (Service Connect)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Salida a ECR, SNS, SQS, CloudWatch y RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "PostgreSQL de JOBBI, solo desde las tareas"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL desde ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}
