locals {
  name         = "${var.project_name}-${var.environment}"
  cluster_outputs = nonsensitive(jsondecode(data.aws_secretsmanager_secret_version.cluster.secret_string))
}

data "aws_secretsmanager_secret_version" "cluster" {
  secret_id = "cluster/${var.cluster_name}/main/outputs"
}

data "aws_region" "this" {}
