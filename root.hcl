locals {
  env_cfg = yamldecode(file(find_in_parent_folders("environment.yaml")))

  account_id   = try(local.env_cfg.account_id, "380183619125") # "Development"
  cluster_name = try(local.env_cfg.cluster_name, "development")
  region       = try(local.env_cfg.region, "eu-central-1")

  backend_name   = "our-own-outbe-deploy-${local.cluster_name}"
  backend_region = "eu-central-1"

  base_domain = "our-own.cloud"

  source_path = (startswith(local.env_cfg.template.url, "git::") ?
    "${local.env_cfg.template.url}/terraform?ref=${local.env_cfg.template.ref}" :
    "${get_path_to_repo_root()}/${local.env_cfg.template.url}/${basename(get_terragrunt_dir())}"
  )
}

# Do not retry on every error even obviously unrecoverable
retryable_errors = []

# Localize caches for all stacks under single folder
download_dir = "${get_repo_root()}/.terragrunt-cache/${path_relative_to_include()}"

remote_state {
  backend = "s3"
  config = {
    encrypt        = true
    bucket         = "${local.backend_name}-tf-state"
    key            = "${path_relative_to_include()}.tfstate"
    region         = local.backend_region
    use_lockfile   = true
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider-aws" {
  contents = templatefile(find_in_parent_folders("provider-aws.tftpl"), {
    args = {
      region = local.region
      allowed_account_id = local.account_id
      tags = {
        managed-with = "terraform"
        project      = local.env_cfg.project_name
        environment  = local.env_cfg.environment
      }
    }
  })
  path      = "providers-aws.tf"
  if_exists = "overwrite"
}

generate "provider-aws-dns-manager" {
  contents = templatefile(find_in_parent_folders("provider-aws.tftpl"), {
    args = {
      alias  = "dns_manager"
      region = local.region
      iam_role = "arn:aws:iam::001903202447:role/DNSZoneManager-${local.cluster_name}"
      tags = {
        managed-with = "terraform"
        project      = local.env_cfg.project_name
        environment  = local.env_cfg.environment
      }
    }
  })
  path      = "providers-aws-dns.tf"
  if_exists = "overwrite"
}

inputs = {
  project_name    = local.env_cfg.project_name
  environment     = local.env_cfg.environment
  production_mode = local.env_cfg.production_mode
  cluster_name    = local.cluster_name
  base_domain     = local.base_domain
}
