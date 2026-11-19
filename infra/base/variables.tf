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

variable "db_instance_class" {
  description = "Clase de la instancia RDS (Learner Lab admite hasta db.t3.medium)."
  type        = string
  default     = "db.t3.micro"
}
