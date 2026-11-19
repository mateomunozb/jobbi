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
  # imagen de backend con distinto SERVICE_MODULE.
  #   dns: nombre con el que los demás lo llaman por Service Connect
  backend = {
    gateway              = { module = "gateway", port = 8080, dns = "gateway", env = {} }
    identidad            = { module = "identidad", port = 8001, dns = "identidad", env = {} }
    mercado              = { module = "mercado", port = 8002, dns = "mercado", env = {} }
    contrataciones       = { module = "contrataciones", port = 8003, dns = "contrataciones", env = { SNS_ENABLED = "true" } }
    comunicacion         = { module = "comunicacion", port = 8004, dns = "comunicacion", env = { SQS_ENABLED = "true" } }
    confianza            = { module = "confianza", port = 8005, dns = "confianza", env = { VERIFICACION_REINTENTOS = "true" } }
    monetizacion         = { module = "monetizacion", port = 8000, dns = "monetizacion", env = { SNS_ENABLED = "true", SQS_ENABLED = "true", SQS_HILOS = "2" } }
    verificacion_externa = { module = "verificacion_externa", port = 8010, dns = "verificacion-externa", env = { PORCENTAJE_RECHAZO = "20" } }
  }

  contextos_activos = ["identidad", "mercado", "contrataciones", "comunicacion", "confianza", "monetizacion"]

  entorno_backend = merge(
    local.base.mensajeria,
    {
      APP_VERSION         = var.image_tag
      AWS_PROVEEDOR       = "aws"
      AWS_REGION          = var.aws_region
      CREAR_BASE_SI_FALTA = "true"
      LOG_LEVEL           = "INFO"
      SERVICIOS_ACTIVOS   = join(",", local.contextos_activos)
      VERIFICACION_URL    = "http://verificacion-externa:8010"

      # Contextos no desplegados en AWS: host inexistente → 502 controlado.
      SERVICIO_SOPORTE_URL     = "http://soporte.invalid:8006"
      SERVICIO_ADQUISICION_URL = "http://adquisicion.invalid:8007"
      SERVICIO_PROTECCION_URL  = "http://proteccion.invalid:8008"
    },
    { for nombre in local.contextos_activos :
      "SERVICIO_${upper(nombre)}_URL" => "http://${local.backend[nombre].dns}:${local.backend[nombre].port}"
    },
  )
}
