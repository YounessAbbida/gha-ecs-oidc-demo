terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # Local state on purpose: this stack creates the S3 bucket that stores the
  # infra state, so it cannot keep its own state there. The *.tfstate files are
  # gitignored.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Repo      = var.github_repo
    }
  }
}
