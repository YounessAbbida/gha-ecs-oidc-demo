output "alb_url" {
  description = "Public URL of the application."
  value       = "http://${aws_lb.app.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository the deploy workflow pushes to."
  value       = aws_ecr_repository.app.repository_url
}

output "deploy_role_arn" {
  description = "Role assumed by GitHub Actions. Set it as the AWS_DEPLOY_ROLE_ARN repository variable."
  value       = aws_iam_role.deploy.arn
}

output "deploy_role_oidc_subject" {
  description = "The only OIDC sub claim the deploy role accepts."
  value       = local.github_oidc_subject
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}

output "task_family" {
  description = "ECS task definition family."
  value       = aws_ecs_task_definition.app.family
}

output "container_name" {
  description = "Container name inside the task definition."
  value       = local.container_name
}
