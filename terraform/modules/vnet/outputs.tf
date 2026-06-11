output "vnet_id" {
  description = "Resource ID of the Virtual Network."
  value       = azurerm_virtual_network.aks_vnet.id
}

output "vnet_name" {
  description = "Name of the Virtual Network."
  value       = azurerm_virtual_network.aks_vnet.name
}

output "subnet_ids" {
  description = "Map of logical subnet key → subnet resource ID."
  value       = { for k, s in azurerm_subnet.aks_subnet : k => s.id }
}

output "subnet_names" {
  description = "Map of logical subnet key → subnet name."
  value       = { for k, s in azurerm_subnet.aks_subnet : k => s.name }
}
