resource "aws_ecr_repository" "app" {
  # checkov:skip=CKV_AWS_136: AES256 (SSE with ECR-managed keys) is the intended setting; a customer-managed KMS key is not needed for a public demo image.
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"

  # The repository is disposable: terraform destroy removes it even if it holds images.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
