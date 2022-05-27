variable "environment_name" {
  description = "Basic name of the environment. An internal concept for this TF module."
  nullable    = false
  type        = string
}
variable "aws_region" {
  default     = "us-east-1"
  description = "AWS region for the lab."
  nullable    = false
  type        = string
}
variable "cert_owner" {
  description = "Email of the account owner at LetsEncrypt."
  nullable    = false
  type        = string
}
variable "registry_username" {
  description = "Mirrored registry username."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "registry_password" {
  description = "Mirrored registry password."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "rhsm_username" {
  description = "Red Hat subscription username."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "rhel_pull_secret" {
  description = "Red Hat Image Pull secret."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "rhsm_password" {
  description = "Red Hat subscription password."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "bastion_hostname" {
  description = "Hostname for the bastion server."
  nullable    = false
  type        = string
}
variable "quay_hostname" {
  description = "Hostname for the quay server."
  nullable    = false
  type        = string
}
variable "ssh_public_key" {
  description = "File name containing public SSH key added to all instances created with this plan."
  nullable    = false
  type        = string
}
variable "ssh_private_key" {
  description = "File name containing private SSH key used for remote execution on instances."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "route_53_zone_id" {
  description = "Zone identifier for the Route 53 instance."
  nullable    = false
  type        = string
}
