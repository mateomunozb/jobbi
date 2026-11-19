# Mensajería asíncrona entre contextos (Pub/Sub + Transactional Outbox).
# Equivale a scripts/init-aws-local.sh, pero en AWS real y por ambiente:
#
#   contratacion-completada (SNS)  Contrataciones → Monetización
#       └─► monetizacion-events (SQS) ──5 fallos──► monetizacion-events-dlq
#   billetera-bloqueada (SNS)      Monetización → Comunicación
#       └─► comunicacion-events (SQS) ──5 fallos──► comunicacion-events-dlq

locals {
  flujos = {
    monetizacion = { topic = aws_sns_topic.contratacion_completada, queue = aws_sqs_queue.monetizacion }
    comunicacion = { topic = aws_sns_topic.billetera_bloqueada, queue = aws_sqs_queue.comunicacion }
  }
}

# Tópicos cifrados con la llave administrada de AWS (aws/sns); las colas usan
# SSE-SQS. Ninguna de las dos exige crear llaves KMS propias (LabRole).
resource "aws_sns_topic" "contratacion_completada" {
  name              = "${local.name_prefix}-contratacion-completada-topic"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic" "billetera_bloqueada" {
  name              = "${local.name_prefix}-billetera-bloqueada-topic"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sqs_queue" "monetizacion_dlq" {
  name                      = "${local.name_prefix}-monetizacion-events-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "monetizacion" {
  name                       = "${local.name_prefix}-monetizacion-events-queue"
  visibility_timeout_seconds = 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.monetizacion_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "comunicacion_dlq" {
  name                      = "${local.name_prefix}-comunicacion-events-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "comunicacion" {
  name                       = "${local.name_prefix}-comunicacion-events-queue"
  visibility_timeout_seconds = 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.comunicacion_dlq.arn
    maxReceiveCount     = 5
  })
}

# En AWS real (a diferencia de LocalStack) SNS solo puede escribir en la cola
# si la política de la cola se lo permite explícitamente.
resource "aws_sqs_queue_policy" "desde_sns" {
  for_each  = local.flujos
  queue_url = each.value.queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PermitirSNS"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = each.value.queue.arn
      Condition = { ArnEquals = { "aws:SourceArn" = each.value.topic.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "cola" {
  for_each  = local.flujos
  topic_arn = each.value.topic.arn
  protocol  = "sqs"
  endpoint  = each.value.queue.arn

  depends_on = [aws_sqs_queue_policy.desde_sns]
}
