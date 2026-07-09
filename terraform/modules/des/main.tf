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
  depends_on = [azurerm_disk_encryption_set.aks]
}

# grant the Managed Identity of the Disk Encryption Set "Reader" access to the Key Vault
#### reader not enough
#resource "azurerm_role_assignment" "disk-encryption-read-keyvault" {
#  scope                = var.key_vault_id
#  role_definition_name = "Reader"
#  principal_id         = azurerm_disk_encryption_set.aks.identity[0].principal_id
#}

resource "azurerm_role_assignment" "des_crypto_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_disk_encryption_set.aks.identity[0].principal_id
}

# static wait of 30 sec. not enough
#resource "time_sleep" "wait_for_policy_propagation" {
#  depends_on      = [azurerm_key_vault_access_policy.des]
#  create_duration = "30s"
#}

resource "null_resource" "wait_for_des_access" {
  depends_on = [azurerm_key_vault_access_policy.des]
  triggers = {
    access_policy_id = azurerm_key_vault_access_policy.des.id
  }
  provisioner "local-exec" {
    command = <<-EOT
      for i in $(seq 1 30); do
        az keyvault show \
          --name ${var.key_vault_name} \
          --query "properties.accessPolicies[?objectId=='${azurerm_disk_encryption_set.aks.identity[0].principal_id}']" \
          -o tsv | grep -q . && exit 0
        echo "Waiting for access policy propagation... ($i/30)"
        sleep 10
      done
      echo "Timed out waiting for Key Vault access"
      exit 1
    EOT
  }
}