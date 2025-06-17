locals {
  cert_domain_name_wildcard  = "*.${var.environment}.${var.project_name}.${var.base_domain}"
  validation_domain_names = ["${var.project_name}.${var.base_domain}"]
}

module "env_certificate_wildcard" {
  source = "git@gitlab.base.our-own.cloud:base/tools/terraform-library.git//modules/aws/acm-certificate?ref=v1.11.8"

  domain_name = local.cert_domain_name_wildcard
  validation_domain_name_list = toset(local.validation_domain_names)

  #alternative_domain_names = []

  tags = {
    Name = "${var.environment}-${var.project_name}-${var.base_domain}"
    version-timestamp = timestamp()

    "gateway-name-id/${format(var.gateway_name_template, "private")}"    = "1"
    "gateway-name-id/${format(var.gateway_name_template, "internal")}"   = "1"
    "gateway-name-id/${format(var.gateway_name_template, "public")}"     = "1"
  }

  providers = {
    aws.dns_manager = aws.dns_manager
  }
}
