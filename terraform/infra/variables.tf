variable "aws_region" {
  description = "AWS region for the workload."
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Name used for the ECR repository, ECS cluster, service and task family. The deploy workflow uses the same value."
  type        = string
  default     = "gha-ecs-oidc-demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}$", var.project_name))
    error_message = "project_name must be lowercase, start with a letter and be at most 23 characters (ALB and target group names are limited to 32)."
  }
}

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/name. Case-sensitive: it must match the OIDC sub claim exactly."
  type        = string
  default     = "YounessAbbida/gha-ecs-oidc-demo"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must be owner/name, without wildcards."
  }
}

variable "github_environment" {
  description = "GitHub environment allowed to deploy. Only jobs running in this environment can assume the deploy role."
  type        = string
  default     = "production"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_environment))
    error_message = "github_environment must be a plain environment name, without wildcards."
  }
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub repository owner. Set it (with github_repo_id) when the repository uses GitHub's immutable OIDC subject format, the default for repositories created after 2026-07-15. Leave empty for the legacy owner/name format."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[0-9]*$", var.github_owner_id))
    error_message = "github_owner_id must be the numeric owner ID, or empty."
  }
}

variable "github_repo_id" {
  description = "Numeric ID of the GitHub repository. Set together with github_owner_id, or leave both empty."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[0-9]*$", var.github_repo_id)) && ((var.github_repo_id == "") == (var.github_owner_id == ""))
    error_message = "github_repo_id must be numeric and set together with github_owner_id (or both left empty)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "desired_count" {
  description = "Number of running tasks. Keep 0 until the first image has been pushed by the deploy workflow, then set to 1."
  type        = number
  default     = 0

  validation {
    condition     = var.desired_count >= 0 && var.desired_count <= 2
    error_message = "desired_count must be between 0 and 2 for this demo."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the application logs."
  type        = number
  default     = 7
}
