variable "aws_region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "gha-ecs-oidc-demo"
}

variable "github_repo" {
  description = "GitHub repository (owner/name). Only used as a tag here."
  type        = string
  default     = "YounessAbbida/gha-ecs-oidc-demo"
}

variable "create_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set to false if the account already has one for token.actions.githubusercontent.com."
  type        = bool
  default     = true
}

variable "budget_limit_usd" {
  description = "Monthly cost budget for the account, in USD."
  type        = number
  default     = 10
}

variable "budget_email" {
  description = "Email address that receives budget alerts."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_email))
    error_message = "budget_email must be a valid email address."
  }
}

variable "state_bucket_force_destroy" {
  description = "Allow terraform destroy to delete the state bucket even if it still holds state versions. Keep false except for final teardown."
  type        = bool
  default     = false
}
