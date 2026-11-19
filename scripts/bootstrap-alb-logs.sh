#!/usr/bin/env bash
# Crea y configura el bucket S3 de access logs de los ALB de un ambiente.
#
# Va fuera de Terraform porque una SCP de AWS Academy niega
# s3:GetBucketObjectLockConfiguration, que el recurso aws_s3_bucket siempre
# consulta. Idempotente: el job deploy-infra lo ejecuta antes de cada apply.
#
#   scripts/bootstrap-alb-logs.sh <staging|production>
set -euo pipefail

ENTORNO="${1:?Uso: bootstrap-alb-logs.sh <staging|production>}"
REGION="${AWS_REGION:-us-east-1}"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="jobbi-$ENTORNO-alb-logs-$CUENTA"

# Cuenta de Elastic Load Balancing que entrega los logs en la región
# (regiones anteriores a agosto de 2022 usan una cuenta por región).
case "$REGION" in
  us-east-1) ELB_CUENTA=127311923021 ;;
  us-east-2) ELB_CUENTA=033677994240 ;;
  us-west-1) ELB_CUENTA=027434742980 ;;
  us-west-2) ELB_CUENTA=797873946194 ;;
  *) echo "Región $REGION sin cuenta de ELB configurada" >&2; exit 2 ;;
esac

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "✓ El bucket $BUCKET ya existe"
elif [[ "$REGION" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  echo "✓ Bucket $BUCKET creado"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  echo "✓ Bucket $BUCKET creado"
fi

aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-ownership-controls --bucket "$BUCKET" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
# Los access logs de ALB solo admiten SSE-S3 (AES256).
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration \
  '{"Rules":[{"ID":"expirar-logs","Status":"Enabled","Filter":{},"Expiration":{"Days":30}}]}'

POLITICA=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EntregaDeLogsDeLosAlb",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::$ELB_CUENTA:root" },
      "Action": "s3:PutObject",
      "Resource": [
        "arn:aws:s3:::$BUCKET/alb/AWSLogs/$CUENTA/*",
        "arn:aws:s3:::$BUCKET/alb-interno/AWSLogs/$CUENTA/*"
      ]
    },
    {
      "Sid": "SoloTls",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::$BUCKET", "arn:aws:s3:::$BUCKET/*"],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
JSON
)
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$POLITICA"
echo "✓ $BUCKET: privado, cifrado, solo TLS, expiración 30 días, escritura para ELB"
