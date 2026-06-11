output "disk_encryption_set_id" {
  description = "Resource ID of the Disk Encryption Set — pass to AKS as disk_encryption_set_id."
  value       = azurerm_disk_encryption_set.aks.id
}

output "disk_encryption_set_name" {
  description = "Name of the Disk Encryption Set."
  value       = azurerm_disk_encryption_set.aks.name
}

output "key_vault_key_id" {
  description = "Resource ID of the Key Vault key."
  value       = azurerm_key_vault_key.aks_disk.id
}

output "principal_id" {
  description = "Principal ID of the Disk Encryption Set managed identity — useful for additional RBAC assignments."
  value       = azurerm_disk_encryption_set.aks.identity[0].principal_id
}
