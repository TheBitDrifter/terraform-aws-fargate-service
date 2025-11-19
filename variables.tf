# Service Details (Inputs for Immutability and Scale)
variable "aws_region" {
  description = "The AWS region to deploy to."
  type        = string
}

variable "service_name" {
  description = "Mandatory, unique service identifier (e.g., 'user-api'). Enforces resource naming convention."
  type        = string
}

variable "image_url" {
  description = "Full ECR digest/tag URL for the immutable deployment artifact."
  type        = string
}

variable "container_port" {
  description = "Application port exposed by the Docker container. Must align with app/Dockerfile configuration."
  type        = number
  default     = 3000
}

variable "cpu" {
  description = "CPU units provisioned for Fargate task execution. Optimize for cost/performance."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory (in MiB) provisioned for Fargate task."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Minimum count for task resiliency. Set to >1 for AZ redundancy."
  type        = number
  default     = 1
}

# Platform References (Where to Plug In)
variable "vpc_id" {
  description = "ID of the parent VPC. Required for networking context."
  type        = string
}

variable "private_subnet_ids" {
  description = "Target private subnets for Fargate task placement. Enforces isolation."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security Group IDs to enforce least-privilege network access on the ECS tasks. Should allow ingress from the ALB."
  type        = list(string)
}

variable "ecs_cluster_id" {
  description = "ID of the central ECS cluster where tasks will be scheduled."
  type        = string
}

variable "api_gateway_id" {
  description = "ID of the shared HTTP API Gateway for public exposure."
  type        = string
}

variable "vpc_link_id" {
  description = "ID of the VPC Link, used to route traffic securely from API GW into the VPC."
  type        = string
}

# --- AUTO SCALING ---
variable "min_capacity" {
  description = "Minimum number of tasks to run."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks to run."
  type        = number
  default     = 5
}

variable "cpu_threshold" {
  description = "CPU utilization % to trigger scaling."
  type        = number
  default     = 70
}

variable "memory_threshold" {
  description = "Memory utilization % to trigger scaling."
  type        = number
  default     = 70
}

variable "alb_listener_arn" {
  description = "ARN of the shared internal ALB listener. Used to attach the new routing rule."
  type        = string
}

# Routing Details
variable "path_pattern" {
  description = "The path pattern for the ALB Listener Rule (e.g., '/api/v1/users/*'). Must be unique across all services."
  type        = string
}

variable "api_route_key" {
  description = "The API Gateway route key (e.g., 'ANY /users/{proxy+}'). Defines the public contract."
  type        = string
}
