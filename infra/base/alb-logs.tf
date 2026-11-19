# Access logs de los ALB (público e interno) en S3.
#
# El bucket NO lo administra Terraform: una SCP de AWS Academy niega
# s3:GetBucketObjectLockConfiguration, y el recurso aws_s3_bucket siempre lo
# consulta. Lo crea y configura scripts/bootstrap-alb-logs.sh (idempotente),
# que el job deploy-infra ejecuta antes de este apply: privado, cifrado SSE-S3,
# solo TLS, expiración a 30 días y permiso de escritura para Elastic Load
# Balancing. destroy.yml lo borra al destruir el ambiente.

data "aws_caller_identity" "current" {}

locals {
  alb_logs_bucket = "${local.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"
}
