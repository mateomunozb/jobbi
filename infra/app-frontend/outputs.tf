output "alb_url" {
  description = "URL pública del ambiente."
  value       = local.base.alb_url
}

output "image_tag" {
  description = "Versión del frontend desplegada (tag de imagen)."
  value       = var.image_tag
}
