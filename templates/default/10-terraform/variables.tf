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

variable "production_mode" {
  type    = bool
  default = false
}

variable "cluster_name" {
  type = string
}

variable "az_suffix" {
  default     = "b"
  description = "Suffix of availability zone to use in case of single AZ deployment"
}

variable "multi-az" {
  type    = bool
  default = false
}

