# Estado remoto de Terraform (compartido por infra/shared, infra/base e infra/app).
# Cada raíz fija su propia "key"; cada ambiente es un workspace (env:/<ambiente>/...).
# El bucket se crea una sola vez con scripts/bootstrap-tfstate.sh.
bucket       = "tfstate-jobbi-mateomunozb"
region       = "us-east-1"
use_lockfile = true
