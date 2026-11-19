# PostgreSQL administrado: una instancia por ambiente y una base por contexto
# (jobbi_identidad, jobbi_mercado, …). Cada servicio crea su base al arrancar
# (CREAR_BASE_SI_FALTA), igual que el init del StatefulSet en Kubernetes.

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "app" {
  name       = "${local.name_prefix}-db"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "app" {
  identifier     = "${local.name_prefix}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"

  username = "jobbi"
  password = random_password.db.result
  db_name  = "postgres"

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  # Ambiente académico: sin snapshots ni backups para poder destruirlo rápido.
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}

# Cadena de conexión de cada contexto como secreto (SecureString): ECS la
# inyecta al contenedor sin que aparezca en texto plano en la task definition.
resource "aws_ssm_parameter" "database_url" {
  for_each = toset(local.contextos_con_base)

  name  = "/jobbi/${var.environment_name}/database-url/${each.key}"
  type  = "SecureString"
  value = "postgresql+psycopg://jobbi:${random_password.db.result}@${aws_db_instance.app.address}:5432/jobbi_${each.key}"
}
