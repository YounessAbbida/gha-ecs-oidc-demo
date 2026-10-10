# ---------------------------------------------------------------------------
# Roles assumed by ECS, not by GitHub.
#   execution role: used by the ECS agent to pull the image and write logs
#   task role:      used by the application code; it needs no AWS access
# ---------------------------------------------------------------------------

# Execution role trust: the documented ECS trust policy. It is assumed by the
# ECS agent before the task starts, so no task-level condition applies here.
data "aws_iam_policy_document" "execution_trust" {
  statement {
    sid     = "EcsTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Task role trust: same principal plus the confused-deputy condition AWS
# recommends for task roles: only ECS acting for this account. (AWS also
# documents aws:SourceArn, but only as a wildcard over all clusters, so the
# exact-match account condition is used instead.)
data "aws_iam_policy_document" "task_trust" {
  statement {
    sid     = "EcsTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-ecs-execution"
  description        = "ECS agent: pull the app image and write its logs"
  assume_role_policy = data.aws_iam_policy_document.execution_trust.json
}

# Scoped replacement for the AWS managed AmazonECSTaskExecutionRolePolicy,
# which allows pulling from every repository and writing to every log group.
data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # Action has no resource-level permissions.
  }

  statement {
    sid    = "EcrPullThisRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "WriteAppLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "pull-image-and-write-logs"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# No policies attached: the app does not call any AWS API. Having an explicit,
# empty task role keeps it that way and makes the intent reviewable.
resource "aws_iam_role" "task" {
  name               = "${var.project_name}-ecs-task"
  description        = "Application role: no permissions"
  assume_role_policy = data.aws_iam_policy_document.task_trust.json
}
