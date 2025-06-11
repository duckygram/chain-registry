resource "aws_kms_key" "secrets" {
  description = "Key to encrypt secrets of ${var.project_name}/${var.environment}"
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-${var.environment}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}
