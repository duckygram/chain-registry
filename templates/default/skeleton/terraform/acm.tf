data "aws_route53_zone" "system" {
  for_each     = var.system_list
  name         = "${each.key}.${var.base_domain}"
  private_zone = false
  provider     = aws.dns_manager
}

locals {
  names_per_cert_limit        = var.names_per_cert_limit # AWS limit for number of names per ACM certificate (10 by default)
  alter_names_per_cert_limit  = local.names_per_cert_limit - 1
  cert_domain_name_wildcard   = "*.${var.environment}.environment.${var.base_domain}"
  cert_other_domain_wildcards = [for s in var.system_list : "*.${var.environment}.${s}.${var.base_domain}"]
  cert_domain_name_apex       = "${var.environment}.environment.${var.base_domain}"
  cert_other_domain_apexes    = [for s in var.system_list : "${var.environment}.${s}.${var.base_domain}"]
  domain_set                  = toset([for s in setunion(var.system_list, ["environment"]) : "${s}.${var.base_domain}"])
}

module "env_certificate_wildcard" {
  count       = ceil(length(local.domain_set) / local.alter_names_per_cert_limit)
  source      = "git@gitlab.base.our-own.cloud:base/tools/terraform-library.git//modules/aws/acm-certificate?ref=v1.11.8"
  domain_name = local.cert_domain_name_wildcard
  alternative_domain_names = slice(local.cert_other_domain_wildcards,
    count.index * local.alter_names_per_cert_limit,
  min((count.index + 1) * local.alter_names_per_cert_limit, length(local.cert_other_domain_wildcards)))
  validation_domain_name_list = local.domain_set

  tags = {
    Name              = "${var.project_name}-${var.environment}.${var.base_domain}-${count.index}"
    version-timestamp = timestamp()

    "gateway-name-id/${format(var.gateway_name_template, "private")}"    = "1"
    "gateway-name-id/${format(var.gateway_name_template, "internal")}"   = "1"
    "gateway-name-id/${format(var.gateway_name_template, "public")}"     = "1"
    "gateway-name-id/${format(var.gateway_name_template, "restricted")}" = "1"
  }

  providers = {
    aws.dns_manager = aws.dns_manager
  }
}

#module "env_certificate_apexes" {
#  count = ceil(length(local.domain_set)/local.alter_names_per_cert_limit)
#  source                      = "git@gitlab.base.our-own.cloud:base/tools/terraform-library.git//modules/aws/acm-certificate?ref=v1.6.1"
#  domain_name                 = local.cert_domain_name_apex
#  alternative_domain_names    = slice(local.cert_other_domain_apexes,
#    count.index * local.alter_names_per_cert_limit,
#    min((count.index + 1) * local.alter_names_per_cert_limit, length(local.cert_other_domain_apexes)))
#  validation_domain_name_list = local.domain_set
#
#  tags = {
#    Name              = "${var.environment}.${var.base_domain}-${count.index}"
#    version-timestamp = timestamp()
#
#    "gateway-name-id/${format(var.gateway_name_template, "private")}"  = "1"
#    "gateway-name-id/${format(var.gateway_name_template, "internal")}" = "1"
#    # "gateway-name-id/${format(var.gateway_name_template,"public")}" = "1"
#  }
#
#  providers = {
#    aws.dns_manager = aws.dns_manager
#  }
#}
