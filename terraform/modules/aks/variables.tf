variable "location" {
  type = string
  default     = "westus3"
}

variable "resource_group_name" {
  type = string
}

variable "managed_cluster_name" {
  type = string
}

variable "admin_username" {
  type      = string
  sensitive = true
}

variable "ssh_rsa_public_key" {
  type      = string
  sensitive = true
}

variable "apiserver_subnet_id" {
  description = "Subnet ID for API Server VNet Integration."
  type        = string
}

variable "system_subnet_id" {
  description = "Subnet ID for the system node pool."
  type        = string
}

variable "user_subnet_id" {
  description = "Subnet ID for the user node pool."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default = {
  }
}

variable "disk_encryption_set_id" {
  description = "Resource ID of the Disk Encryption Set — pass to AKS as disk_encryption_set_id."
  type          = string
}