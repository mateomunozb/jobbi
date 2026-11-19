variable "aws_region" {
  description = "Región de AWS (AWS Academy Learner Lab trabaja en us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "environment_name" {
  description = "Ambiente a desplegar; también es el workspace de Terraform."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment_name)
    error_message = "environment_name debe ser 'staging' o 'production'."
  }
}

variable "tfstate_bucket" {
  description = "Bucket S3 con el estado de Terraform (para leer la capa base)."
  type        = string
}

variable "image_tag" {
  description = "Tag de la imagen jobbi/frontend en ECR (hash de frontend/). También es la versión que reporta /healthz."
  type        = string
}

variable "desired_count" {
  description = "Réplicas del frontend."
  type        = number
  default     = 1
}
