# ===========================================================================
# GitHub Actions deploy role
#
# Who can assume it:  only a workflow job in ${var.github_repo} that runs in
#                     the "${var.github_environment}" GitHub environment.
# What it can do:     push images to one ECR repository, register task
#                     definitions, update one ECS service, and pass the two
#                     task roles to ECS. Nothing else.
# How long:           1 hour maximum session, no long-lived keys anywhere.
# ===========================================================================

locals {
  github_oidc_host = "token.actions.githubusercontent.com"

  # The repository part of the sub claim. Repositories created after
  # 2026-07-15 use GitHub's immutable format, which adds the numeric owner and
  # repository IDs (owner@123/repo@456). That format also stops a renamed or
  # re-created repository with the same name from matching.
  github_repo_owner   = split("/", var.github_repo)[0]
  github_repo_name    = split("/", var.github_repo)[1]
  github_repo_subject = var.github_repo_id == "" ? var.github_repo : "${local.github_repo_owner}@${var.github_owner_id}/${local.github_repo_name}@${var.github_repo_id}"

  # Exact subject claim GitHub puts in the OIDC token for a job that declares
  # `environment: <name>`. A job without that environment (a PR, another
  # branch, a fork, another repository) gets a different sub and is rejected.
  github_oidc_subject = "repo:${local.github_repo_subject}:environment:${var.github_environment}"
}

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    sid     = "GitHubActionsOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # The token was minted for AWS STS, not for another relying party.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Exact match, no wildcards: this repository, this environment, nothing else.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = [local.github_oidc_subject]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.project_name}-gha-deploy"
  description          = "Assumed by GitHub Actions (${local.github_oidc_subject}) to deploy to ECS"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  # Needed for `docker login` to ECR. This action has no resource-level
  # permissions; the token alone grants nothing without the repository
  # actions below.
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push (and the layer checks docker does during a push) to this one repository.
  statement {
    sid    = "EcrPushPullThisRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # Read the current revision and register the next one. Resource "*" as in
  # AWS's documented minimum policy for this flow: DescribeTaskDefinition has
  # no resource-level permissions, and the new revision has no ARN until
  # RegisterTaskDefinition creates it.
  statement {
    sid    = "EcsTaskDefinitions"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }

  # Roll out the new revision on this one service and wait for it to be stable.
  statement {
    sid    = "EcsDeployThisService"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = [aws_ecs_service.app.arn]
  }

  # A task definition references the execution and task roles, so registering
  # it requires iam:PassRole on them. The condition stops these roles from
  # being passed to anything other than ECS tasks (no EC2, no Lambda, ...).
  statement {
    sid     = "PassOnlyTaskRolesToEcsTasks"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.execution.arn,
      aws_iam_role.task.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy-to-ecs"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
