# Azure Free Tier 12-Month Plan For ~$25 Budget/Credit [~$2 per month] — CLI Commands (Simplified Notes)

### ‼️NOTE: 
- This plan is for users with a budget/credits ≤$25 for 12 months, or ≤$4 per month for 12 consecutive months and a domain name managed by Cloudflare DNS (which is free).
- This plan includes 3 VMs: `B2ats v2` — 2 vCPUs, 1 GB RAM (AMD/x64), `B2pts v2` — 2 vCPUs, 1 GB RAM (ARM64), `B1s` — 1 vCPU, 1 GB RAM (AMD/x64)
- All 3 VMs will run on Latest Ubuntu 24.04 LTS. You can customize this according to your need, (if you want to customize, than please modify step: 9 accordingly)
- Two VMs (both AMD/x64 — B1s and B2ats v2) will use **P6 Premium free-tier 64 GB SSD OS disks**. The ARM64 VM (B2pts v2) will use **P6 Premium free-tier 64 GB SSD OS disk** as well.
- (If you want to customize anything according to your need, please modify Step: 7 and/or Step 9 accordingly)

This document summarizes the Azure CLI commands to set up the Free Tier 12-Month environment with Cloudflare Tunnel integration, eliminating public IP costs. Scroll mid-page for Azure Cloud Shell CLI commands.

***

## Step 0 — Variables

* Subscription, resource group, and VM names stored in variables.
* Location: Central India
* RG: free-tier-12mo-rg
* VNet + Subnet + NSG defined.
* Storage account created for boot diagnostics.

***

## Step 1 — Confirm Subscription

Check active subscription with:

* `az account show`

***

## Step 2 — Create Resource Group

* `az group create` to create RG.

***

## Step 3 — Create VNet + Subnet

* `az network vnet create` with address space 10.10.0.0/16 and subnet 10.10.1.0/24.

***

## Step 4 — Create NSG + Rules

* Allow SSH (22) only from your public IP.
* Allow HTTP (80) and HTTPS (443) from Internet.

***

## Step 5 — Public IP

* Only mgmt-vm gets a Public IP (temporarily for Cloudflare setup).
* Use **Standard** SKU.

***

## Step 6 — Create NICs

* sprt-nic (private)
* mgmt-nic (with public IP, bound to mgmt-pip)
* powr-nic (private)

***

## Step 7 — Storage Account

* Created for boot diagnostics.

***

## Step 9 — VM Creation

* **sprt-vm:** Ubuntu 24.04 LTS, size Standard_B1s, 64 GB Premium SSD disk.
* **mgmt-vm:** Ubuntu 24.04 LTS, size Standard_B2ats_v2, 64 GB Premium SSD disk, public IP (temporary).
* **powr-vm:** Ubuntu 24.04 LTS ARM64, size Standard_B2pts_v2, 64 GB Premium SSD disk, Trusted Launch (Secure Boot + vTPM disabled).

***

## Step 10 — Enable Boot Diagnostics

Enabled for all three VMs using the storage account.

***

## Step 11 — Get Public IP (mgmt-vm)

* Retrieve mgmt-vm IP with `az network public-ip show`.

***

## Step 12 — Validation

* List all VMs with `az vm list`.
* List all NICs with `az network nic list`.

***

## Step 13 — Connect to Cloudflare Tunnel

* If you got a domain name with DNS on Cloudflare than we will tunnel to that domain, and further we will remove IP address from our setup.
* Followed by step 14 to delete PIP.

***

## Step 14 — Remove Public IP

* Delete public IP to eliminate ongoing costs after Cloudflare tunnel setup.

***

## Summary

* Three VMs with comprehensive compute resources (total: 5 vCPUs, 3 GB RAM)
* One management VM with temporary public IP. **Cost: ~$3.66/month for 1-2 hrs setup only**
* Two workload VMs (sprt-vm and powr-vm) with private IPs only.
* All VMs with P6 64GB Premium SSD (12-month free tier eligible)
* Cloudflare tunnel eliminates ongoing public IP costs
* Centralized NSG with inbound rules for SSH, HTTP, and HTTPS.
* Boot diagnostics enabled via a storage account.
* **Final Monthly Cost: ~$4/month after public IP removal**

***

# Full Step-by-Step Commands
## ^Rename variables according to your convenience.
## ^Run Step 0 every time you start a new Cloud Shell session before continuing.

## Step 0 — Variables

```bash
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

```bash
az account show --query "{name:name, id:id, tenantId:tenantId}" -o json
```

## Step 2 — Create resource group

```bash
az group create --name $RG --location $LOCATION
```

## Step 3 — Create VNet + Subnet

```bash
az network vnet create \
--resource-group $RG \
--name $VNET_NAME \
--address-prefixes 10.10.0.0/16 \
--subnet-name $SUBNET_NAME \
--subnet-prefixes 10.10.1.0/24
```

## Step 4 — Create NSG + Rules

```bash
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

## Step 5 — Public IP (temporary for setup only)

```bash
az network public-ip create \
-g $RG \
-n mgmt-pip \
--sku Standard \
--version IPv4
```

## Step 6 — Create NICs

```bash
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

```bash
az storage account create --name $SA_NAME --resource-group $RG --location $LOCATION --sku Standard_LRS --kind StorageV2
STORAGE_URI=$(az storage account show -g $RG -n $SA_NAME --query "primaryEndpoints.blob" -o tsv)
```

## Step 9 — VM Creation

```bash
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

# mgmt-vm (x64, P6 Premium SSD 64GB, temporary public IP)
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

# powr-vm (ARM64, P6 Premium SSD 64GB, TrustedLaunch overrides)
az vm create -g $RG -n $VM3 --nics $POW_NIC_ID \
--image Canonical:ubuntu-24_04-lts:server-arm64:latest \
--size Standard_B2pts_v2 \
--admin-username azureuser \
--generate-ssh-keys \
--storage-sku Premium_LRS \
--os-disk-size-gb 64 \
--security-type TrustedLaunch \
--enable-secure-boot false \
--enable-vtpm false
```

## Step 10 — Enable boot diagnostics

```bash
az vm boot-diagnostics enable --resource-group $RG --name $VM1 --storage $STORAGE_URI
az vm boot-diagnostics enable --resource-group $RG --name $VM2 --storage $STORAGE_URI
az vm boot-diagnostics enable --resource-group $RG --name $VM3 --storage $STORAGE_URI
```

## Step 11 — Get public IP (mgmt-vm only)

```bash
az network public-ip show -g $RG -n mgmt-pip --query ipAddress -o tsv
```

## Step 12 — Validation

```bash
az vm list -g $RG -o table
az network nic list -g $RG -o table
```

## Step 13 — Install Cloudflare Tunnel on mgmt-vm

SSH into mgmt-vm first, then follow these steps: (^‼️Route the tunnel to your domain - replace mgmt.example.com with your actual domain or subdomain)

```bash
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
  - hostname: mgmt.example.com
    service: ssh://localhost:22
  - service: http_status:404
EOF

# route tunnel through Cloudflare DNS (NOT nameserver!)
cloudflared tunnel route dns azure-mgmt-tunnel mgmt.example.com

# run tunnel as service (persistent)
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
```

^‼️Route the tunnel to your domain (replace mgmt.example.com with your actual domain or subdomain)

## Step 14 — Remove Public IP Completely

Once Cloudflare tunnel works and is accessible via your domain, detach + delete PIP to eliminate ongoing costs:

```bash
# Detach PIP from NIC
az network nic ip-config update \
-g $RG \
-n ipconfig1 \
--nic-name mgmt-nic \
--remove publicIpAddress

# Delete the PIP resource
az network public-ip delete -g $RG -n mgmt-pip
```

Now all VMs have only private IPs, with mgmt-vm accessible through Cloudflare Tunnel.
This eliminates ~$3.66/month ongoing cost for static public IP, reducing total monthly cost to ~$4/month.

## Access Your VMs

After setup completion:
- **mgmt-vm**: Access via `ssh azureuser@mgmt.example.com` (through Cloudflare tunnel)
- **sprt-vm & powr-vm**: Access via mgmt-vm as jump host using private IPs (10.10.1.x)

Total infrastructure cost: **~$25/year (~$2/month)** with 3 VMs providing 5 vCPUs and 3GB RAM total.
