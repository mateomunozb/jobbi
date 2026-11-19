# Capa BASE de un ambiente de JOBBI (staging o production): todo lo que no
# cambia con cada versión de la aplicación.
#
#   red (security groups) · ALB público · ALB interno (comunicación entre
#   servicios) · RDS PostgreSQL · SNS/SQS · cluster ECS · logs
#
# La capa APP (infra/app: task definitions y servicios ECS) se despliega encima
# y lee estas salidas del estado remoto. Separarlas permite que el pipeline
# muestre "Deploy Infra" y "Deploy App" como etapas distintas, y que un
# rollback solo toque la capa de aplicación.
#
#   terraform workspace select -or-create staging
#   terraform apply -var environment_name=staging
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Bucket y región en "terraform init -backend-config=../backend.hcl".
  backend "s3" {
    key = "jobbi/base.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "jobbi"
      Environment = var.environment_name
      Layer       = "base"
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  name_prefix = "jobbi-${var.environment_name}"

  # Contextos con base de datos propia en RDS.
  contextos_con_base = ["identidad", "mercado", "contrataciones", "comunicacion", "confianza", "monetizacion"]

  # Servicios del backend que se llaman entre sí (y el frontend al gateway) a
  # través del ALB interno: un listener por puerto. "corto" se usa en nombres
  # de AWS con límite de 32 caracteres (target groups).
  servicios_internos = {
    gateway              = { port = 8080, corto = "gw" }
    identidad            = { port = 8001, corto = "ident" }
    mercado              = { port = 8002, corto = "merc" }
    contrataciones       = { port = 8003, corto = "contr" }
    comunicacion         = { port = 8004, corto = "comun" }
    confianza            = { port = 8005, corto = "conf" }
    monetizacion         = { port = 8000, corto = "monet" }
    verificacion_externa = { port = 8010, corto = "verif" }
  }
}

# --- Recursos existentes que Terraform solo consulta ------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }

  filter {
    name   = "availability-zone"
    values = ["${var.aws_region}a", "${var.aws_region}b"]
  }
}

# --- Cluster ECS ---------------------------------------------------------------
# El descubrimiento entre servicios lo hace el ALB interno (alb-interno.tf): el
# Learner Lab no permite crear namespaces de Cloud Map, así que no hay Service
# Connect.

resource "aws_ecs_cluster" "app" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 14
}

# Versiones por componente (backend y frontend se despliegan por separado):
#   current-version    lo que está desplegado ahora (lo escribe el deploy)
#   last-good-version  lo último que pasó el smoke (punto de retorno del rollback)
# El pipeline decide qué desplegar comparando la versión deseada con current-version.
locals {
  parametros_version = {
    for par in setproduct(["backend", "frontend"], ["current-version", "last-good-version"]) :
    "${par[0]}/${par[1]}" => par
  }
}

resource "aws_ssm_parameter" "version" {
  for_each = local.parametros_version

  name  = "/jobbi/${var.environment_name}/${each.key}"
  type  = "String"
  value = "none"

  lifecycle {
    ignore_changes = [value]
  }
}
