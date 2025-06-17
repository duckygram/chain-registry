include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = include.root.locals.source_path
}

inputs = {
  # most base values are inherited from root.hcl
}
