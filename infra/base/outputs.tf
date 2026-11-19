# Salidas que consume la capa APP (infra/app) por terraform_remote_state.

output "alb_url" {
  description = "URL pública del ambiente."
  value       = "http://${aws_lb.app.dns_name}"
}

output "cluster_arn" {
  value = aws_ecs_cluster.app.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.app.name
}

output "alb_interno_dns" {
  description = "DNS del ALB interno: los servicios se llaman como http://<dns>:<puerto>."
  value       = aws_lb.interno.dns_name
}

output "internal_target_group_arns" {
  description = "Target group del ALB interno de cada servicio del backend."
  value       = { for nombre, tg in aws_lb_target_group.interno : nombre => tg.arn }
}

output "subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}

output "frontend_target_group_arn" {
  value = aws_lb_target_group.frontend.arn
}

output "gateway_target_group_arn" {
  value = aws_lb_target_group.gateway.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "database_url_parameter_arns" {
  description = "ARN del parámetro SSM con la cadena de conexión de cada contexto."
  value       = { for nombre, p in aws_ssm_parameter.database_url : nombre => p.arn }
}

output "mensajeria" {
  description = "Nombres de temas y colas, tal como los leen los servicios."
  value = {
    SNS_TOPIC_NAME                = aws_sns_topic.contratacion_completada.name
    SNS_TOPIC_BILLETERA_BLOQUEADA = aws_sns_topic.billetera_bloqueada.name
    QUEUE_NAME                    = aws_sqs_queue.monetizacion.name
    QUEUE_DLQ_NAME                = aws_sqs_queue.monetizacion_dlq.name
    QUEUE_COMUNICACION            = aws_sqs_queue.comunicacion.name
    QUEUE_COMUNICACION_DLQ        = aws_sqs_queue.comunicacion_dlq.name
  }
}

output "rds_endpoint" {
  value = aws_db_instance.app.address
}

output "version_parameters" {
  description = "Parámetros SSM de versión por componente (current / last-good)."
  value       = { for clave, p in aws_ssm_parameter.version : clave => p.name }
}
