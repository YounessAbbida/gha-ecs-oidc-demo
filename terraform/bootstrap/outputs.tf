output "state_bucket_name" {
  description = "S3 bucket for the infra stack's state. Put it in terraform/infra/backend.hcl."
  value       = aws_s3_bucket.state.bucket
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider."
  value       = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}
