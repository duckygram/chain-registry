output "secrets_kms_key_id" {
  value = aws_kms_key.secrets.key_id
}

output "default_data_key_id" {
  value = nonsensitive(local.main_outputs.default_data_key_id)
}
