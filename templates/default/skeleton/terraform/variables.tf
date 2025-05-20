variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "base_domain" {
  type = string
}

variable "gateway_name_template" {
  default = "istio-ingress/istio-ingressgateway-%s"
}

variable "names_per_cert_limit" {
  default     = 50
  description = "Max number of names in ACM SSL certificate. Default AWS limit is 10. It is possible to increase the limit to at least 100"
}

variable "system_list" {
  type = set(string)
  default = [
    "outbe",
  ]
}

variable "production_mode" {
  type    = bool
  default = false
}

variable "cluster_name" {
  type = string
}
