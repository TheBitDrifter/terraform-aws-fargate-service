output "service_url" {
  description = "The URL of the service"
  value       = "${data.aws_apigatewayv2_api.this.api_endpoint}/${var.service_name}"
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = var.create_ecr ? aws_ecr_repository.this[0].repository_url : data.aws_ecr_repository.this[0].repository_url
}
