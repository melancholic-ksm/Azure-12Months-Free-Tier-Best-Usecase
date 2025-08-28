# Azure Free Tier 12-Month Plan For \~\$0.99 Budget/Credit [\~\$0.99 per month]  — CLI Commands (Simplified Notes)

### ‼️NOTE: - This plan is for users with a budget/credits ≤$0.99 for the 1st month and a domain name managed by Cloudflare DNS (which is free).
- In this plan you get 2 VM's, `B2ats v2` with 2vcpu and 1GB RAM {AMD x64}, `B2pts v2` with 2vcpu and 1GB RAM {ARM64} or `Bs1` 1vcpu and 1GB RAM {intel x64}.
- Both VM's will work on Latest Ubuntu 24.04 Lts. You can customize this according to your need, (if you want to customize, than please modify step: 9A/ 9B accordingly)
- One VM (B2ats v2, AMD/x64) will use a P6 Premium free-tier 64GB SSD OS disk. The other (B2pts v2, ARM64) or (B1s, intel x64) will also use a P6 Premium free-tier 64GB SSD OS disk. (if you want to customize anything according to your need, please modify Step: 9A/ 9B)

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

* mgmt-nic (with public IP, bound to mgmt-pip)
* powr-nic or sprt-nic (private)

---

## Step 9 — VM Creation

* **mgmt-vm:** Ubuntu 24.04 LTS, size Standard\_B2ats\_v2, 64GB disk, public IP.
* **powr-vm:** Ubuntu 24.04 LTS ARM64, size Standard\_B2pts\_v2, 32GB disk, No Trusted Launch*

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

## Step 13 - Connect to Cloudflare Tunnel

* If you got a domain name with dns on cloudflare than we will tunnel to that domain, and further we will remove IP address from our setup.

* followed by step 14 to delete pip.

## Summary

* One management VM with a static public IP (Standard SKU). **Cost: \~\$3.66/month, and we just need 1-2 hrs for setting up cloudflare tunnel (approx \$1)** (just required to connect mgmt-vm and setup Cloudflare tunnel and than we will remove PIP)
* One workload VM (powr-vm or sprt-vm) with private IPs only.
* Two VMs with P6 64GB SSD (for 12 Months only)
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

# Step 7 — Create storage account for boot diagnostics
az storage account create \
  --name $SA_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS

STORAGE_URI=$(az storage account show -g $RG -n $SA_NAME --query "primaryEndpoints.blob" -o tsv)


# Choose one option based on your requirement. 
 - **9A- {B2ats+B2pts [mgmt-vm+powr-vm]-- in total 4vcpu and 2 GB RAM, but One is AMD x64 and Other one ARM64}.**
 - **9B- {B2ats+B1s [mgmt-vm+sprt-vm]-- in total 3vcpu and 2 GB RAM, both X64 (AMD and intel)}.**

## Step 9A — VM Creation (B2ats + B2pts)

```
MGT_NIC_ID=$(az network nic show -g $RG -n mgmt-nic --query id -o tsv)
POW_NIC_ID=$(az network nic show -g $RG -n powr-nic --query id -o tsv)

# mgmt-vm (x64)
az vm create -g $RG -n $VM2 --nics $MGT_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B2ats_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Premium_LRS \
  --os-disk-size-gb 64

# enable standard security feature (needed for powr-vm)
az feature register --namespace Microsoft.Compute --name UseStandardSecurityType
az provider register --namespace Microsoft.Compute

# powr-vm (ARM64, override TrustedLaunch)
az vm create -g $RG -n $VM3 --nics $POW_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server-arm64:latest \
  --size Standard_B2pts_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Standard_LRS \
  --os-disk-size-gb 32 \
  --security-type Standard

```

## Step 9B — VM Creation (B2ats + B1s)

```
SPR_NIC_ID=$(az network nic show -g $RG -n sprt-nic --query id -o tsv)
MGT_NIC_ID=$(az network nic show -g $RG -n mgmt-nic --query id -o tsv)

# sprt-vm (x64)
az vm create -g $RG -n $VM1 --nics $SPR_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Premium_LRS \
  --os-disk-size-gb 64

# mgmt-vm (x64)
az vm create -g $RG -n $VM2 --nics $MGT_NIC_ID \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B2ats_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Premium_LRS \
  --os-disk-size-gb 64

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

## Step 13 — Install Cloudflare Tunnel on mgmt-vm

SSH into mgmt-vm first, then follow these steps: (^‼️Route the tunnel to your domain (replace mgmt.example.com with your actual domain or subdomain))

```
ssh azureuser@$(az network public-ip show -g $RG -n mgmt-pip --query ipAddress -o tsv)

# install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# login to Cloudflare (browser opens, select your domain)
cloudflared tunnel login

# create tunnel
cloudflared tunnel create azure-mgmt-tunnel

# create config file
mkdir -p ~/.cloudflared
cat <<EOF > ~/.cloudflared/config.yml
tunnel: azure-mgmt-tunnel
credentials-file: /home/azureuser/.cloudflared/$(ls ~/.cloudflared/*.json)

ingress:
  - hostname: mgmt.example.com^
    service: ssh://localhost:22
  - service: http_status:404
EOF

# route tunnel through Cloudflare DNS (NOT nameserver!)
cloudflared tunnel route dns azure-mgmt-tunnel mgmt.example.com^

# run tunnel
cloudflared tunnel run azure-mgmt-tunnel
```

^‼️Route the tunnel to your domain (replace mgmt.example.com with your actual domain or subdomain)

## Step 14 — Remove Public IP Completely

Once Cloudflare tunnel works, detach + delete PIP:

```
# Detach PIP from NIC
az network nic ip-config update \
  -g $RG \
  -n ipconfig1 \
  --nic-name mgmt-nic \
  --remove publicIpAddress

# Delete the PIP resource
az network public-ip delete -g $RG -n mgmt-pip
```


Now mgmt-vm has only private IP, accessible only through Cloudflare Tunnel.
This eliminates ~$3.66/mo cost for static IP.

##
