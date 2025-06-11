include "root" {
  path   = find_in_parent_folders("root-system.hcl")
  expose = true
}

terraform {
  source = include.root.locals.source_path
}

# TODO: get cluster outputs from special secret
inputs = {
  az_suffix = "c"
  allow_cidr_blocks = [
    "10.192.4.0/22", # OurOwnCloud VPN
    "10.193.0.0/19"  # Infra Cluster, CI jobs
  ]
  base_domain = include.root.locals.base_domain
}
