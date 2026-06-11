variable "key_vault_id" {
  description = "Resource ID of the existing Key Vault where the key will be created."
  type        = string
}

variable "key_name" {
  description = "Name of the Key Vault key used for disk encryption."
  type        = string
  default     = "aks-disk-encryption-key"
}

variable "disk_encryption_set_name" {
  description = "Name of the Disk Encryption Set resource."
  type        = string
  default     = "des-aks"
}

variable "location" {
  description = "Azure region for the Disk Encryption Set."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group in which to create the Disk Encryption Set."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
