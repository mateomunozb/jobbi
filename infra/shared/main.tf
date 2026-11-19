# Recursos COMPARTIDOS por todos los ambientes: los repositorios de imágenes.
#
# Build once, deploy many: el CI publica una sola vez cada imagen (tag = SHA del
# commit) y staging y production despliegan exactamente ese mismo artefacto.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "jobbi/shared.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "jobbi"
      Layer     = "shared"
      ManagedBy = "Terraform"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

resource "aws_ecr_repository" "app" {
  for_each = toset(["backend", "frontend"])

  name = "jobbi/${each.key}"
  # Un tag publicado no se puede sobrescribir: el SHA identifica un único build,
  # y el rollback depende de que la imagen anterior siga siendo la misma.
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  # Escaneo de vulnerabilidades del sistema operativo de la imagen en cada push.
  image_scanning_configuration {
    scan_on_push = true
  }
}

# Conserva las últimas 30 imágenes: suficiente para varios rollbacks sin
# acumular costo de almacenamiento.
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conservar las ultimas 30 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_urls" {
  value = { for nombre, repo in aws_ecr_repository.app : nombre => repo.repository_url }
}

output "registry" {
  value = split("/", aws_ecr_repository.app["backend"].repository_url)[0]
}
