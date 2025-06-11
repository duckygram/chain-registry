locals {
  name         = "${var.project_name}-${var.environment}"
  main_outputs = nonsensitive(jsondecode(data.aws_secretsmanager_secret_version.main.secret_string))
}

data "aws_secretsmanager_secret_version" "main" {
  secret_id = "cluster/${var.cluster_name}/main/outputs"
}

data "aws_region" "this" {}
