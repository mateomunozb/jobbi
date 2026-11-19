#!/usr/bin/env bash
# Crea (una sola vez) el bucket S3 del estado remoto de Terraform.
#
# Es el único recurso que no administra Terraform: Terraform necesita el bucket
# antes de poder guardar su propio estado. Idempotente.
#
#   aws configure   # o exportar las credenciales temporales del Learner Lab
#   ./scripts/bootstrap-tfstate.sh
set -euo pipefail

BUCKET="${1:-tfstate-jobbi-mateomunozb}"
REGION="${AWS_REGION:-us-east-1}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "✓ El bucket $BUCKET ya existe"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  echo "✓ Bucket $BUCKET creado"
fi

# Versionado: permite recuperar un estado anterior si un apply lo corrompe.
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "✓ Versionado y bloqueo de acceso público activos"
