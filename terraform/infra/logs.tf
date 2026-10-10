resource "aws_cloudwatch_log_group" "app" {
  # checkov:skip=CKV_AWS_158: Default CloudWatch Logs encryption is used; a KMS key would outlive this short-lived demo and add cost.
  # checkov:skip=CKV_AWS_338: 7-day retention is deliberate: the environment lives for a few hours.
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days
}
