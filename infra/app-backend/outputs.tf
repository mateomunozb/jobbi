output "alb_url" {
  description = "URL pública del ambiente."
  value       = local.base.alb_url
}

output "image_tag" {
  description = "Versión del backend desplegada (tag de imagen)."
  value       = var.image_tag
}

output "services" {
  value = [for s in aws_ecs_service.backend : s.name]
}
