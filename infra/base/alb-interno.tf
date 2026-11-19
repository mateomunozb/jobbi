# ALB interno: comunicación entre servicios dentro de la VPC.
#
# Reemplaza a ECS Service Connect, que el Learner Lab no permite (no deja crear
# namespaces de Cloud Map). Cada servicio del backend tiene un listener en su
# puerto y un target group propio, así que se sigue desplegando y escalando
# por separado. Los demás lo llaman como http://<dns-interno>:<puerto>
# (variables SERVICIO_*_URL), igual que con el nombre de un Service de
# Kubernetes. No es accesible desde Internet (internal = true).

resource "aws_lb" "interno" {
  name               = "${local.name_prefix}-int"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_interno.id]
  subnets            = data.aws_subnets.default.ids
  # El gateway mantiene WebSockets abiertos hacia Comunicación.
  idle_timeout               = 300
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    bucket  = local.alb_logs_bucket
    prefix  = "alb-interno"
    enabled = true
  }
}

resource "aws_lb_target_group" "interno" {
  for_each = local.servicios_internos

  name                 = "${local.name_prefix}-${each.value.corto}-i"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.default.id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Tráfico interno de la VPC (sin dominio ni certificado en el Learner Lab).
resource "aws_lb_listener" "interno" {
  for_each = local.servicios_internos

  load_balancer_arn = aws_lb.interno.arn
  port              = each.value.port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.interno[each.key].arn
  }
}
