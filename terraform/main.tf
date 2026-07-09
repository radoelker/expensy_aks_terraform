locals {
  kv_resource_group_name = "${var.resource_group_name}-kv"
  # KV names: max 24 chars, globally unique, alphanumeric + hyphens only
  # Result: kv-aks-prod-bicep-001 = 21 chars
  kv_name = "kv-${substr(var.managed_cluster_name, 0, 14)}-${var.kv_suffix}"
}

# ── Resource Groups ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "cluster" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_resource_group" "keyvault" {
  name     = local.kv_resource_group_name
  location = var.location
}


# ── Key Vault Module ───────────────────────────────────────────────────────────
module "keyvault" {
  source = "./modules/keyvault"

  location                = var.location
  resource_group_name     = azurerm_resource_group.keyvault.name
  kv_name                 = local.kv_name
  deployer_object_id      = var.deployer_object_id
  deployer_principal_type = var.deployer_principal_type
  admin_username          = var.admin_username
  ssh_rsa_public_key      = var.ssh_rsa_public_key
  tags = merge(
    {
      module = "keyvault"
    },
    var.tags
  )
}

data "azurerm_key_vault" "existing" {
  name                = local.kv_name
  resource_group_name = azurerm_resource_group.keyvault.name
}

# ── Vnet Module ─────────────────────────────────────────────────────────────────
# including API Server VNet Integration
module "vnet" {
  source = "./modules/vnet"

  tags = merge(
    {
      module = "vnet"
    },
    var.tags
  )

  vnet_name           = "vnet-aks-prod"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.1.0.0/16"]

  subnets = {
    # System node pool — nodes only, pods use pod_cidr via CNI Overlay
    aks_system = {
      name             = "snet-aks-system"
      address_prefixes = ["10.1.0.0/28"] # 14 usable IPs → ~14 nodes max
    }

    # User / workload node pool
    aks_user = {
      name             = "snet-aks-user"
      address_prefixes = ["10.1.1.0/28"] # 14 usable IPs → ~14 nodes max
    }

    # API Server VNet Integration — Azure injects its NIC here.
    # /28 is the minimum Azure requires; keep this subnet dedicated.
    aks_apiserver = {
      name             = "snet-aks-apiserver"
      address_prefixes = ["10.1.2.0/28"] # 11 usable IPs — Azure minimum
      delegation = {
        name                       = "aks-apiserver-delegation"
        service_delegation_name    = "Microsoft.ContainerService/managedClusters"
        service_delegation_actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }

}


module "des" {
  source              = "./modules/des"
  key_vault_id        = data.azurerm_key_vault.existing.id
  key_vault_name      = data.azurerm_key_vault.existing.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags = merge(
    {
      module = "des"
    },
    var.tags
  )
  #depends_on = [module.keyvault]
}


# ── AKS Module ─────────────────────────────────────────────────────────────────
# depends_on is explicit: ESO Managed Identity RBAC (added in a later step)
# will be assigned against the KV, so AKS must wait for the KV to be ready.
# Secrets are passed directly as variables — no round-trip getSecret() needed
# because the values are already in memory as sensitive TF variables.
module "aks" {
  source = "./modules/aks"

  tags = merge(
    {
      module = "aks"
    },
    var.tags
  )
  disk_encryption_set_id = module.des.disk_encryption_set_id
  apiserver_subnet_id    = module.vnet.subnet_ids["aks_apiserver"]
  system_subnet_id       = module.vnet.subnet_ids["aks_system"]
  user_subnet_id         = module.vnet.subnet_ids["aks_user"]
  location               = var.location
  resource_group_name    = azurerm_resource_group.cluster.name
  managed_cluster_name   = var.managed_cluster_name
  admin_username         = var.admin_username
  ssh_rsa_public_key     = var.ssh_rsa_public_key

  #depends_on = [module.keyvault, module.vnet, module.des]
  depends_on = [module.des]
}
