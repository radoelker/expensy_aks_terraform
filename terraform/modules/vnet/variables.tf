variable "vnet_name" {
  description = "Name of the Virtual Network."
  type        = string
}

variable "location" {
  description = "Azure region for the VNet."
  type        = string
  default     = "westus3"
}

variable "resource_group_name" {
  description = "Resource group in which to create the VNet."
  type        = string
}

variable "address_space" {
  description = "CIDR blocks for the VNet address space."
  type        = list(string)
}

variable "subnets" {
  description = <<-EOT
    Map of subnets to create. Key is a logical identifier used to reference
    subnet IDs downstream (e.g. "aks_system", "aks_user", "aks_apiserver").

    delegation is optional — only set it for subnets that require Azure to
    inject managed infrastructure (e.g. API Server VNet Integration,
    PostgreSQL Flexible Server, etc.).
  EOT
  type = map(object({
    name             = string
    address_prefixes = list(string)
    delegation = optional(object({
      name                       = string
      service_delegation_name    = string
      service_delegation_actions = list(string)
    }))
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default = {
  }
}
