# Capa APP-BACKEND de un ambiente de JOBBI: los 8 servicios ECS del backend.
#
# Se despliega de forma independiente del frontend (pipeline del backend): un
# cambio en services/ solo reemplaza estas tareas, y su rollback solo re-aplica
# esta capa con el tag anterior. Lee la capa BASE del estado remoto.
#
#   terraform workspace select -or-create staging
#   terraform apply -var environment_name=staging -var image_tag=<tag> -var tfstate_bucket=<bucket>
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "jobbi/app-backend.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "jobbi"
      Environment = var.environment_name
      Layer       = "app-backend"
      ManagedBy   = "Terraform"
    }
  }
}

# Salidas de infra/base en el mismo workspace (staging o production).
data "terraform_remote_state" "base" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket = var.tfstate_bucket
    key    = "jobbi/base.tfstate"
    region = var.aws_region
  }
}

# AWS Academy no permite crear roles IAM: tareas y agente de ECS usan LabRole.
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

data "aws_ecr_repository" "backend" {
  name = "jobbi/backend"
}

locals {
  name_prefix = "jobbi-${var.environment_name}"
  base        = data.terraform_remote_state.base.outputs

  # Núcleo del flujo de contratación desplegado en AWS. Todos corren la misma
  # imagen de backend con distinto SERVICE_MODULE. Los puertos coinciden con
  # los listeners del ALB interno (infra/base/main.tf: servicios_internos).
  backend = {
    gateway              = { module = "gateway", port = 8080, env = {} }
    identidad            = { module = "identidad", port = 8001, env = {} }
    mercado              = { module = "mercado", port = 8002, env = {} }
    contrataciones       = { module = "contrataciones", port = 8003, env = { SNS_ENABLED = "true" } }
    comunicacion         = { module = "comunicacion", port = 8004, env = { SQS_ENABLED = "true" } }
    confianza            = { module = "confianza", port = 8005, env = { VERIFICACION_REINTENTOS = "true" } }
    monetizacion         = { module = "monetizacion", port = 8000, env = { SNS_ENABLED = "true", SQS_ENABLED = "true", SQS_HILOS = "2" } }
    verificacion_externa = { module = "verificacion_externa", port = 8010, env = { PORCENTAJE_RECHAZO = "20" } }
  }

  # Los servicios se llaman entre sí por el ALB interno: http://<dns>:<puerto>.
  interno = "http://${local.base.alb_interno_dns}"

  contextos_activos = ["identidad", "mercado", "contrataciones", "comunicacion", "confianza", "monetizacion"]

  entorno_backend = merge(
    local.base.mensajeria,
    {
      APP_VERSION         = var.image_tag
      JOBBI_AMBIENTE      = var.environment_name
      AWS_PROVEEDOR       = "aws"
      AWS_REGION          = var.aws_region
      CREAR_BASE_SI_FALTA = "true"
      LOG_LEVEL           = "INFO"
      SERVICIOS_ACTIVOS   = join(",", local.contextos_activos)
      VERIFICACION_URL    = "${local.interno}:${local.backend.verificacion_externa.port}"

      # Contextos no desplegados en AWS: host inexistente → 502 controlado.
      SERVICIO_SOPORTE_URL     = "http://soporte.invalid:8006"
      SERVICIO_ADQUISICION_URL = "http://adquisicion.invalid:8007"
      SERVICIO_PROTECCION_URL  = "http://proteccion.invalid:8008"
    },
    { for nombre in local.contextos_activos :
      "SERVICIO_${upper(nombre)}_URL" => "${local.interno}:${local.backend[nombre].port}"
    },
  )
}
