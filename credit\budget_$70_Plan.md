# Azure Free Tier 12-Month Plan (~$70 budget / ~$6 per month) — CLI Commands (Simplified Notes)

### ‼️Note:
This plan is for users with a budget/credits ≤$70 for 12 months, or ≤$6 per month for 12 consecutive months.
No Domain name is necessary, if you got one you can use the other plan where it will cost you \$20 for 12 month.

- This plan includes 3 VMs:
  • `B2ats v2` — 2 vCPUs, 1 GB RAM (AMD/x64)  
  • `B2pts v2` — 2 vCPUs, 1 GB RAM (ARM64)  
  • `B1s` — 1 vCPU, 1 GB RAM (AMD/x64)

- All 3 VMs will run on the latest Ubuntu 24.04 LTS.  
  (You may customize this; if so, update Step 9 accordingly.)

- Two VMs (both AMD/x64 — B1s and B2ats v2) will use **P6 Premium free-tier 64 GB SSD OS disks**.  
  The ARM64 VM (B2pts v2) will use an **S4 Standard 32 GB HDD OS disk**.  
  (If customized, update Step 7 and/or Step 9 accordingly.)

This document summarizes the Azure CLI commands to set up the Free Tier 12-Month environment, finalized with a single mgmt-vm Public IP approach.  
Scroll mid-page for Azure Cloud Shell CLI commands.

---

## Step 0 — Variables

* Subscription, resource group, and VM names stored in variables.
* Location: Central India
* RG: free-tier-12mo-rg
* VNet + Subnet + NSG defined.
* Storage account created for boot diagnostics.

---

## Step 1 — Confirm Subscription

* `az account show`

---

## Step 2 — Create Resource Group

* `az group create` to create RG.

---

## Step 3 — Create VNet + Subnet

* `az network vnet create` with address space 10.10.0.0/16 and subnet 10.10.1.0/24.

---

## Step 4 — Create NSG + Rules

* Allow SSH (22) only from your public IP.
* Allow HTTP (80) and HTTPS (443) from the Internet.

---

## Step 5 — Public IP

* Only mgmt-vm gets a Public IP.
* Use **Standard** SKU.

---

## Step 6 — Create NICs

* sprt-nic (private)  
* mgmt-nic (with public IP, bound to mgmt-pip)  
* powr-nic (private)

---

## Step 7 — Storage Account

* Created for boot diagnostics.

---

## Step 9 — VM Creation

* **sprt-vm:** Ubuntu 24.04 LTS, size Standard_B1s, 64 GB disk.  
* **mgmt-vm:** Ubuntu 24.04 LTS, size Standard_B2ats_v2, 64 GB disk, public IP.  
* **powr-vm:** Ubuntu 24.04 LTS ARM64, size Standard_B2pts_v2, 32 GB disk, Trusted Launch (Secure Boot + vTPM disabled).

---

## Step 10 — Enable Boot Diagnostics

Enabled for all three VMs using the storage account.

---

## Step 11 — Get Public IP (mgmt-vm)

* Retrieve mgmt-vm IP with `az network public-ip show`.

---

## Step 12 — Validation

* List all VMs with `az vm list`.  
* List all NICs with `az network nic list`.

---

## Summary

* One management VM with a static public IP (Standard SKU). **Cost: ~$3.66/month**  
* Two workload VMs (sprt-vm and powr-vm) with private IPs only.  
* Two VMs with P6 64 GB SSD (12-month free tier).  
* One VM with S4 32 GB HDD (minimal possible disk). **Cost: ~$2/month**  
* Centralized NSG with inbound rules for SSH, HTTP, and HTTPS.  
* Boot diagnostics enabled via a storage account.

---

# Full Step-by-Step Commands 
## ^Rename variables according to your convenience.  
## ^Run Step 0 every time you start a new Cloud Shell session before continuing.

## Step 0 — Variables

```
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
LOCATION="centralindia"
RG="free-tier-12mo-rg"
VNET_NAME="free-tier-vnet"
SUBNET_NAME="free-tier-subnet"
NSG_NAME="free-tier-nsg"
SA_NAME="bootdiag$RANDOM"

VM1="sprt-vm"
VM2="mgmt-vm"
VM3="powr-vm"
```

## Step 1 — Confirm subscription

```
az account show --query "{name:name, id:id, tenantId:tenantId}" -o json
```

## Step 2 — Create resource group
```
az group create --name $RG --location $LOCATION
```

## Step 3 — Create VNet + Subnet

```
az network vnet create \
  --resource-group $RG \
  --name $VNET_NAME \
  --address-prefixes 10.10.0.0/16 \
  --subnet-name $SUBNET_NAME \
  --subnet-prefixes 10.10.1.0/24
```

## Step 4 — Create NSG + Rules

```
az network nsg create -g $RG -n $NSG_NAME

az network nsg rule create -g $RG --nsg-name $NSG_NAME -n Allow-SSH \
  --protocol Tcp --priority 1000 --destination-port-ranges 22 \
  --access Allow --direction Inbound --source-address-prefixes YOUR_PUBLIC_IP/32

az network nsg rule create -g $RG --nsg-name $NSG_NAME -n Allow-HTTP \
  --protocol Tcp --priority 1010 --destination-port-ranges 80 \
  --access Allow --direction Inbound --source-address-prefixes Internet

az network nsg rule create -g $RG --nsg-name $NSG_NAME -n Allow-HTTPS \
  --protocol Tcp --priority 1020 --destination-port-ranges 443 \
  --access Allow --direction Inbound --source-address-prefixes Internet
  ```

## Step 5 — Public IP (only mgmt-vm)

```
az network public-ip create \
  -g $RG \
  -n mgmt-pip \
  --sku Standard \
  --version IPv4
```

## Step 6 — Create NICs
```
az network nic create -g $RG -n sprt-nic \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --network-security-group $NSG_NAME

az network nic create -g $RG -n mgmt-nic \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --network-security-group $NSG_NAME \
  --public-ip-address mgmt-pip

az network nic create -g $RG -n powr-nic \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --network-security-group $NSG_NAME
  ```

## Step 7 — Storage account for boot diagnostics

```
az storage account create --name $SA_NAME --resource-group $RG --location $LOCATION --sku Standard_LRS --kind StorageV2
STORAGE_URI=$(az storage account show -g $RG -n $SA_NAME --query "primaryEndpoints.blob" -o tsv)
```

## Step 9 — VM Creation

```
## Step 9 — VM Creation

SPR_NIC_ID=$(az network nic show -g $RG -n sprt-nic --query id -o tsv)
MGT_NIC_ID=$(az network nic show -g $RG -n mgmt-nic --query id -o tsv)
POW_NIC_ID=$(az network nic show -g $RG -n powr-nic --query id -o tsv)

# sprt-vm (x64, Free Tier eligible with P6 Premium SSD 64GB)
az vm create -g $RG -n $VM1 --nics $SPR_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Premium_LRS \
  --os-disk-size-gb 64

# mgmt-vm (x64, P6 Premium SSD 64GB, public IP)
az vm create -g $RG -n $VM2 --nics $MGT_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B2ats_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Premium_LRS \
  --os-disk-size-gb 64

# turning standard security on (for powr-vm)
az feature register --namespace Microsoft.Compute --name UseStandardSecurityType
az provider register --namespace Microsoft.Compute

# powr-vm (ARM64, cheapest Standard HDD 32GB, TrustedLaunch overrides)
az vm create -g $RG -n $VM3 --nics $POW_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server-arm64:latest \
  --size Standard_B2pts_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Standard_LRS \
  --os-disk-size-gb 32 \
  --security-type TrustedLaunch \
  --enable-secure-boot false \
  --enable-vtpm false
  ```

## Step 10 — Enable boot diagnostics
```
az vm boot-diagnostics enable --resource-group $RG --name $VM1 --storage $STORAGE_URI
az vm boot-diagnostics enable --resource-group $RG --name $VM2 --storage $STORAGE_URI
az vm boot-diagnostics enable --resource-group $RG --name $VM3 --storage $STORAGE_URI
```

## Step 11 — Get public IP (mgmt-vm only)
```
az network public-ip show -g $RG -n mgmt-pip --query ipAddress -o tsv
```

## Step 12 — Validation
```
az vm list -g $RG -o table
az network nic list -g $RG -o table
```
