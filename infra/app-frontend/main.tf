# Capa APP-FRONTEND de un ambiente de JOBBI: el servicio ECS de Next.js.
#
# Se despliega de forma independiente del backend (pipeline del frontend): un
# cambio en frontend/ solo reemplaza esta tarea, y su rollback solo re-aplica
# esta capa. Llega al gateway por el ALB interno (capa base, puerto 8080), así
# que no depende del estado de Terraform del backend, solo de que esté desplegado.
#
#   terraform workspace select -or-create staging
#   terraform apply -var environment_name=staging -var image_tag=<tag> -var tfstate_bucket=<bucket>
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "jobbi/app-frontend.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "jobbi"
      Environment = var.environment_name
      Layer       = "app-frontend"
      ManagedBy   = "Terraform"
    }
  }
}

data "terraform_remote_state" "base" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket = var.tfstate_bucket
    key    = "jobbi/base.tfstate"
    region = var.aws_region
  }
}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

data "aws_ecr_repository" "frontend" {
  name = "jobbi/frontend"
}

locals {
  name_prefix = "jobbi-${var.environment_name}"
  base        = data.terraform_remote_state.base.outputs
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name_prefix}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = "${data.aws_ecr_repository.frontend.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      name          = "http"
      containerPort = 3000
      protocol      = "tcp"
      appProtocol   = "http"
    }]

    environment = [
      { name = "APP_VERSION", value = var.image_tag },
      # El proxy /api del servidor de Next llega al gateway por el ALB interno.
      { name = "API_GATEWAY_URL", value = "http://${local.base.alb_interno_dns}:8080" },
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/healthz || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = local.base.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "frontend"
      }
    }
  }])
}

resource "aws_ecs_service" "frontend" {
  name            = "frontend"
  cluster         = local.base.cluster_arn
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.base.subnet_ids
    security_groups  = [local.base.ecs_security_group_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = local.base.frontend_target_group_arn
    container_name   = "frontend"
    container_port   = 3000
  }

  health_check_grace_period_seconds = 60
  wait_for_steady_state             = true

  lifecycle {
    ignore_changes = [desired_count]
  }
}
