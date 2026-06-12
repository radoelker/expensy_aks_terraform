# AKS Production Deployment — Terraform

Terraform equivalent of the Bicep deployment described in the handoff document.
Targets the same resource configuration (Azure CNI Overlay, ephemeral OS disks,
maintenance windows, OIDC/workload identity, KV secrets CSI driver).

## File structure

```
.
├── providers.tf              # Provider versions + feature flags
├── backend.tf                # Partial backend config (filled via backend.conf)
├── backend.conf.example      # Template — copy to backend.conf (git-ignored)
├── main.tf                   # Root module: RGs + calls all child modules
├── variables.tf              # All input variables with descriptions & defaults
├── outputs.tf                # Post-deploy outputs (cluster name, OIDC URL, etc.)
├── terraform.tfvars.example  # Copy to terraform.tfvars (git-ignored) and fill in
├── .gitignore                # Excludes tfvars, backend.conf, state files
├── modules/
│   ├── keyvault/             # Key Vault + RBAC + secrets
│   ├── vnet/                 # VNet + 3 subnets (system, user, apiserver)
│   ├── des/                  # Disk Encryption Set + KV key rotation
│   └── aks/                  # AKS cluster + 3 node pools (system, infra, user)
└── scripts/
    └── bootstrap-state.sh    # One-time: creates storage account for remote state
```

## Network topology

The vnet module creates a single VNet (`10.1.0.0/16`) with three dedicated subnets:

| Subnet | CIDR | Purpose | Delegation |
|--------|------|---------|------------|
| `snet-aks-system` | `10.1.0.0/28` | System node pool (CoreDNS, kube-system) | None |
| `snet-aks-user` | `10.1.1.0/28` | User workload + infra node pools | None |
| `snet-aks-apiserver` | `10.1.2.0/28` | API Server VNet Integration | Microsoft.ContainerService/managedClusters |

**Pod networking:** Azure CNI Overlay mode with pod CIDR `10.244.0.0/16` (independent of node subnet CIDR).

**API Server access:** Restricted via VNet Integration + subnet delegation. No public IP ranges or NSGs required.

## Node pools

AKS cluster includes three node pools:

1. **systempool** (`systempool`)
   - VM: `Standard_D2pds_v6` (ARM64, 2 cores, 8 GB RAM)
   - Nodes: 2–3 (auto-scale)
   - Taint: `kubernetes.azure.com/scalesetpriority=systempool:NoSchedule`
   - Purpose: Kubernetes system components (CoreDNS, kube-proxy, CSI drivers)
   - Storage: 150 GB ephemeral OS disk, host encryption enabled

2. **infrapool** (`infrapool`)
   - VM: `Standard_D4pds_v6` (ARM64, 4 cores, 16 GB RAM)
   - Nodes: 2–4 (auto-scale)
   - Purpose: Observability stack (Prometheus, Loki, Grafana, ArgoCD)
   - Storage: 150 GB ephemeral OS disk, host encryption enabled

3. **userpool** (`userpool`)
   - VM: `Standard_D4pds_v6`
   - Nodes: 1+ (auto-scale)
   - Purpose: Application workloads (frontend, backend, etc.)
   - Storage: 150 GB ephemeral OS disk, host encryption enabled

**Scaling:** All pools auto-scale based on demand (configured via `auto_scaler_profile`).

## First-time setup

### 1 — Bootstrap remote state (once per environment)

```bash
./scripts/bootstrap-state.sh
```

Copy the printed values into `backend.conf` (from `backend.conf.example`).

### 2 — Prepare credentials

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in subscription_id, deployer_object_id,
# admin_username, ssh_public_key
```

### 3 — Init

```bash
terraform init -backend-config=backend.conf
```

### 4 — Plan

```bash
terraform plan \
  -var="deployer_object_id=$(az ad signed-in-user show --query id -o tsv)"
```

### 5 — Apply

```bash
terraform apply \
  -var="deployer_object_id=$(az ad signed-in-user show --query id -o tsv)"
```

### 6 — Get kubeconfig

```bash
az aks get-credentials \
  --resource-group aks-tf-rainer-rg \
  --name aks-prod-tf-rainer \
  --overwrite-existing

kubectl get nodes -o wide
```

Or use the output:
```bash
terraform output kube_config_command | bash
```

## CI/CD (GitHub Actions / Azure DevOps)

- Set `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` as env vars.
- Set `ARM_USE_OIDC=true` (GitHub OIDC) or supply `ARM_CLIENT_SECRET`.
- Pass `deployer_object_id` as a pipeline secret variable.
- Uncomment `use_oidc = true` in `backend.conf`.

## Security & compliance

### Disk encryption

All node OS disks are encrypted using a **Disk Encryption Set (DES)** with a customer-managed RSA-4096 key:

- Key stored in Key Vault with automatic rotation (expires P365D, notified P29D before expiry)
- DES identity granted `Get`, `WrapKey`, `UnwrapKey` permissions on the KV key
- All VM disks encrypted with this key at rest

### Checkov security considerations

| Check ID | Status | Rationale |
|----------|--------|-----------|
| **CKV_AZURE_6** | Skipped | API server access restricted via VNet Integration + subnet delegation (not IP ranges). Aligns with least-privilege networking. |
| **CKV_AZURE_4** | Skipped | Observability provided by Prometheus/Loki/Grafana stack; Azure Monitor OMS agent not required for this architecture. |
| **CKV_AZURE_117** | Passed | Disk encryption enabled via separate DES module with KV-managed key rotation. |
| **CKV_AZURE_227** | Passed | Host encryption enabled on all node pools (`host_encryption_enabled = true`). |
| **CKV_AZURE_189** | Skipped | Key Vault public access enabled temporarily during initial deployment; restricted post-deployment via network rules. |

### Identity & RBAC

- **AKS identity:** User-Assigned Managed Identity attached to cluster; granted Network Contributor on all subnets pre-deployment
- **Workload identity:** OIDC issuer enabled for pod-to-Azure auth (Workload Identity Federation)
- **Key Vault access:** Deployer gets Secrets Officer role; DES gets key permissions only

## Teardown

```bash
terraform destroy
```

> **Note:** If `purge_protection_enabled = true` (default for production),
> you cannot redeploy with the same Key Vault name until the soft-delete
> retention window expires. Use a unique `key_vault_name` per environment
> or set `kv_purge_protection_enabled = false` in labs.

### Teardown bootstrap (blob storage for tfstate)

Clean teardown order: role assignment first, then container, then storage account, then resource group:

bash

```bash
# 1. Remove the role assignment
az role assignment delete \
  --role "Storage Blob Data Contributor" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope /subscriptions/<suscriptionID>/resourceGroups/aks-tf-state-rg/providers/Microsoft.Storage/storageAccounts/akstfstate37ec108a

# 2. Delete the blob container
az storage container delete \
  --name tfstate \
  --account-name akstfstate37ec108a \
  --auth-mode login

# 3. Delete the storage account
az storage account delete \
  --name akstfstate37ec108a \
  --resource-group aks-tf-state-rg \
  --yes

# 4. Delete the resource group
az group delete \
  --name aks-tf-state-rg \
  --yes --no-wait
```

Steps 2 and 3 are actually redundant — deleting the resource group in step 4 would take everything with it. But going in order is good practice and avoids any soft-delete or lock surprises on the storage account.

One thing to confirm first — make sure you have no live Terraform state in that container that you still need. If there's a `terraform.tfstate` blob in there worth keeping, pull it down before step 2:

bash

```bash
az storage blob download \
  --container-name tfstate \
  --name terraform.tfstate \
  --file ./terraform.tfstate.backup \
  --account-name akstfstate37ec108a \
  --auth-mode login
```

