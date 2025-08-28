# Azure Free Tier 12-Month Plan For \~\$70 Budget/Credit [\~\$6 per month]  — CLI Commands (Simplified Notes)

### ‼️NOTE: - This Plan is for those who have a budget/credits ≤\$70 For 12 Months or ≤\$6 Per Month for 12 consecutive month.
- In this plan you get 3 VM's, `B2ats v2` with 2vcpu and 1GB RAM {AMD/x64}, `B2pts v2` with 2vcpu and 1GB RAM {ARM64}, `B1s` with 1vcpu and 1GB RAM {AMD/x64}
- All 3 VM's will work on Latest Ubuntu 24.04 Lts. You can customize this according to your need, (if you do so, please modify step: 9 accordingly)
- 2 VM's (both AMD/x64--bs1 and b2ats v2) will operate on P6 (Premium Free tier 64GB SSD) Os disk, other one (B2pts ARM64) will operate on S4 (Standard 32 GB HDD) os disk. (if you want to customize anything according to your need, please modify Step: 7 and/or Step: 9)

This document summarizes the Azure CLI commands we used to set up the Free Tier 12-Month environment, finalized with a single mgmt-vm Public IP approach.  Scroll mid page for Azure Cloudshell CLI commands.

---

## Step 0 — Variables

* Subscription, resource group, and VM names stored in variables.
* Location: centralindia
* RG: free-tier-12mo-rg
* VNet + Subnet + NSG defined.
* Storage account created for boot diagnostics.

---

## Step 1 — Confirm Subscription

Check active subscription with:

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
* Allow HTTP (80) and HTTPS (443) from Internet.

---

## Step 5 — Public IP

* Only mgmt-vm gets a Public IP.
* Used `Standard` SKU.

---

## Step 6 — Create NICs

* sprt-nic (private)
* mgmt-nic (public, bound to mgmt-pip)
* powr-nic (private)

---

## Step 7 — Storage Account

* Created for boot diagnostics.

---

## Step 9 — VM Creation

* **sprt-vm:** Ubuntu 24.04 LTS, size Standard\_B1s, 64GB disk.
* **mgmt-vm:** Ubuntu 24.04 LTS, size Standard\_B2ats\_v2, 64GB disk, public IP.
* **powr-vm:** Ubuntu 24.04 LTS ARM64, size Standard\_B2pts\_v2, 32GB disk, TrustedLaunch (with secure boot and vTPM disabled).

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

* One management VM with a static public IP (Standard SKU). **Cost: \~\$3.66/month**
* Two workload VMs (sprt-vm and powr-vm) with private IPs only.
* Two VMs with P6 64GB SSD (for 12 Months only)
* One VM with S4 32 GB HDD (Minimal possible Disk). **Cost: \~\$2/month**
* Centralized NSG with inbound rules for SSH/HTTP/HTTPS.
* Boot diagnostics enabled via a storage account.

---

# Full Step-by-Step Commands 
## ^Rename Variables according to your convenience, ^Make sure to run Step 0 everytime you create new cloudshell and continuing with any step xyz.

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

## Step 5 — Public IP (final method: only mgmt-vm)

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
SPR_NIC_ID=$(az network nic show -g $RG -n sprt-nic --query id -o tsv)
MGT_NIC_ID=$(az network nic show -g $RG -n mgmt-nic --query id -o tsv)
POW_NIC_ID=$(az network nic show -g $RG -n powr-nic --query id -o tsv)

# sprt-vm (x64)
az vm create -g $RG -n $VM1 --nics $SPR_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku StandardSSD_LRS \
  --os-disk-size-gb 64

# mgmt-vm (x64)
az vm create -g $RG -n $VM2 --nics $MGT_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B2ats_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku StandardSSD_LRS \
  --os-disk-size-gb 64

# turning standard security on (for powr-vm)
az feature register --namespace Microsoft.Compute --name UseStandardSecurityType
az provider register --namespace Microsoft.Compute

# powr-vm (ARM64, needs TrustedLaunch overrides)
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

## Step 11 — Get public IP (only mgmt-vm)

```
az network public-ip show -g $RG -n mgmt-pip --query ipAddress -o tsv
```

## Step 12 — Validation

```
az vm list -g $RG -o table
az network nic list -g $RG -o table
```


##
