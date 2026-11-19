# Un servicio ECS por contexto, todos con la misma imagen de backend.

resource "aws_ecs_task_definition" "backend" {
  for_each = local.backend

  family                   = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${data.aws_ecr_repository.backend.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      name          = "http"
      containerPort = each.value.port
      protocol      = "tcp"
      appProtocol   = "http"
    }]

    environment = [
      for clave, valor in merge(local.entorno_backend, each.value.env, {
        SERVICE_MODULE = each.value.module
        PORT           = tostring(each.value.port)
      }) : { name = clave, value = valor }
    ]

    # Cadena de conexión desde SSM (SecureString): no queda en texto plano.
    secrets = contains(keys(local.base.database_url_parameter_arns), each.key) ? [{
      name      = "DATABASE_URL"
      valueFrom = local.base.database_url_parameter_arns[each.key]
    }] : []

    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:${each.value.port}/health', timeout=3)\""]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = local.base.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = each.key
      }
    }
  }])
}

resource "aws_ecs_service" "backend" {
  for_each = local.backend

  name            = replace(each.key, "_", "-")
  cluster         = local.base.cluster_arn
  task_definition = aws_ecs_task_definition.backend[each.key].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Si las tareas nuevas no arrancan sanas, ECS vuelve solo a la revisión
  # anterior (primera línea de rollback, antes que la del pipeline).
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.base.subnet_ids
    security_groups  = [local.base.ecs_security_group_id]
    assign_public_ip = true # subredes públicas por defecto, sin NAT (costo)
  }

  service_connect_configuration {
    enabled   = true
    namespace = local.base.service_connect_namespace_arn

    service {
      port_name      = "http"
      discovery_name = each.value.dns
      client_alias {
        port     = each.value.port
        dns_name = each.value.dns
      }
    }

    log_configuration {
      log_driver = "awslogs"
      options = {
        awslogs-group         = local.base.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "service-connect-${each.key}"
      }
    }
  }

  # Solo el gateway recibe tráfico del ALB; los demás son internos.
  dynamic "load_balancer" {
    for_each = each.key == "gateway" ? [1] : []
    content {
      target_group_arn = local.base.gateway_target_group_arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  health_check_grace_period_seconds = each.key == "gateway" ? 90 : null
  wait_for_steady_state             = true

  lifecycle {
    ignore_changes = [desired_count]
  }
}
