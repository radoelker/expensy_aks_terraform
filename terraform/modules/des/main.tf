resource "azurerm_key_vault_key" "aks_disk" {
  name         = "aks-disk-encryption-key"
  key_vault_id = var.key_vault_id
  key_type     = "RSA"
  key_size     = 4096
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
  rotation_policy {
    automatic {
      time_before_expiry = "P30D"   # rotate 30 days before expiry
    }
    expire_after         = "P365D"  # key expires after 1 year
    notify_before_expiry = "P29D"
  }  
  tags = var.tags
}

resource "azurerm_disk_encryption_set" "aks" {
  name                = "des-aks-prod"
  location            = var.location
  resource_group_name = var.resource_group_name
  key_vault_key_id    = azurerm_key_vault_key.aks_disk.id

  identity {
    type = "SystemAssigned"
  }
  tags = var.tags
}

# Then grant the Disk Encryption Set access to your Key Vault
resource "azurerm_key_vault_access_policy" "des" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_disk_encryption_set.aks.identity[0].tenant_id
  object_id    = azurerm_disk_encryption_set.aks.identity[0].principal_id

  key_permissions = ["Get", "WrapKey", "UnwrapKey"]
}

