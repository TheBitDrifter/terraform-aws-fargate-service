# IAM Role (Enforcing Least Privilege)
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.service_name}-${var.environment}-exec-role"

  # Assumes role policy for ecs-tasks.amazonaws.com
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role = aws_iam_role.ecs_task_execution.name
  # Grants permissions for ECR pull and CloudWatch logging
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- TASK ROLE (App Permissions) ---
# Allows the application code to access AWS services (S3, DynamoDB, etc.)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.service_name}-${var.environment}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# Attach custom policy if provided
resource "aws_iam_role_policy" "ecs_task_role_policy" {
  count = var.task_role_policy_json != null ? 1 : 0
  name  = "${var.service_name}-${var.environment}-task-policy"
  role  = aws_iam_role.ecs_task_role.id
  policy = var.task_role_policy_json
}

# --- ECR REPOSITORY ---
# --- ECR REPOSITORY ---
resource "aws_ecr_repository" "this" {
  count                = var.create_ecr ? 1 : 0
  name                 = lower(coalesce(var.ecr_repository_name, var.service_name))
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # WARNING: Deletes all images when destroyed. Accepted risk for non-prod/demos.

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

data "aws_ecr_repository" "this" {
  count = var.create_ecr ? 0 : 1
  name  = lower(coalesce(var.ecr_repository_name, var.service_name))
}

# CloudWatch Log Group (Observability)
resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/${var.service_name}-${var.environment}"
}

# ECS Task Definition (Immutability Enforced)
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.service_name}-${var.environment}"
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn # Grants permissions to the container

  container_definitions = jsonencode([{
    name      = var.service_name,
    image     = var.image_url, # Reference to the immutable artifact URL
    essential = true,
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }],
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ALB Target Group (Defining Load Balancing Targets)
resource "aws_lb_target_group" "this" {
  name        = "${var.service_name}-${var.environment}"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip" # Required for Fargate
  vpc_id      = var.vpc_id

  health_check {
    path = "/" # Critical: Must point to a reliable health endpoint
  }
}

# ECS Service (Deployment and Scaling Control)
resource "aws_ecs_service" "this" {
  name            = "${var.service_name}-${var.environment}"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Allow app to boot before ALB health checks start killing it
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false # Security enforcement: No public IP in private subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  depends_on = [aws_lb_target_group.this]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ALB Listener Rule (Traffic Routing Enforcement)
resource "aws_lb_listener_rule" "this" {
  listener_arn = var.alb_listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = [var.path_pattern, "/${var.service_name}"]
    }
  }
  priority = var.listener_rule_priority
}

# API Gateway Integration (Public Contract Definition)
resource "aws_apigatewayv2_integration" "this" {
  api_id                 = var.api_gateway_id
  integration_type       = "HTTP_PROXY"
  integration_uri        = var.alb_listener_arn # Routes integration traffic to the specific Target Group
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = var.vpc_link_id
  payload_format_version = "1.0"
}

# Look up the API Gateway to get the endpoint URL
data "aws_apigatewayv2_api" "this" {
  api_id = var.api_gateway_id
}

resource "aws_apigatewayv2_route" "this" {
  api_id    = var.api_gateway_id
  route_key = var.api_route_key
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_apigatewayv2_route" "exact" {
  api_id    = var.api_gateway_id
  route_key = "ANY /${var.service_name}" # Matches "/service" exactly
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

# --- AUTO SCALING ---
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${var.ecs_cluster_id}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_scaling" {
  name               = "${var.service_name}-${var.environment}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.cpu_threshold
  }
}

resource "aws_appautoscaling_policy" "memory_scaling" {
  name               = "${var.service_name}-${var.environment}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = var.memory_threshold
  }
}
