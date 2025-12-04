#!/bin/bash

#===============================================================================
# Azure Free Tier 12-Month Plan (~$70 budget / ~$6 per month)
#===============================================================================
#
# This plan is for users with a budget/credits ≤$70 for 12 months,
# or ≤$6 per month for 12 consecutive months.
#
# This plan includes 3 VMs:
#   • B2ats v2 — 2 vCPUs, 1 GB RAM (AMD/x64)
#   • B2pts v2 — 2 vCPUs, 1 GB RAM (ARM64)
#   • B1s     — 1 vCPU, 1 GB RAM (Intel x64)
#
# All 3 VMs will run on the latest Ubuntu 24.04 LTS. 
#
# Two VMs (B2ats + B1s) use P6 Premium free-tier 64 GB SSD OS disks.
# The B2pts v2 (ARM64) uses an S4 Standard 32 GB HDD OS disk.
#
# Estimated monthly costs:
#   • Public IP (Standard SKU): ~$3.66/month
#   • S4 32 GB HDD disk: ~$2/month
#
#===============================================================================

set -e  # Exit immediately if a command exits with a non-zero status

#-------------------------------------------------------------------------------
# Step 0 — Variables
#-------------------------------------------------------------------------------
# Customize these variables according to your needs

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
LOCATION="centralindia"
RG="free-tier-12mo-rg"
VNET_NAME="free-tier-vnet"
SUBNET_NAME="free-tier-subnet"
NSG_NAME="free-tier-nsg"
# Generate a unique storage account name (must be 3-24 chars, lowercase alphanumeric only)
SA_NAME="bootdiag$(date +%s | tail -c 10)"

VM1="sprt-vm"
VM2="mgmt-vm"
VM3="powr-vm"

echo "=============================================="
echo "Azure Free Tier 12-Month Setup Script"
echo "=============================================="
echo ""

#-------------------------------------------------------------------------------
# Step 1 — Confirm Subscription
#-------------------------------------------------------------------------------
echo "[Step 1] Confirming subscription..."
az account show --query "{name:name, id:id, tenantId:tenantId}" -o json
echo ""

#-------------------------------------------------------------------------------
# Step 2 — Create Resource Group
#-------------------------------------------------------------------------------
echo "[Step 2] Creating resource group: $RG..."
az group create --name "$RG" --location "$LOCATION"
echo ""

#-------------------------------------------------------------------------------
# Step 3 — Create VNet + Subnet
#-------------------------------------------------------------------------------
echo "[Step 3] Creating VNet and Subnet..."
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET_NAME" \
  --address-prefixes 10.10.0.0/16 \
  --subnet-name "$SUBNET_NAME" \
  --subnet-prefixes 10.10.1.0/24
echo ""

#-------------------------------------------------------------------------------
# Step 4 — Public IP (only mgmt-vm)
#-------------------------------------------------------------------------------
echo "[Step 4] Creating public IP for mgmt-vm..."
az network public-ip create \
  --resource-group "$RG" \
  --name mgmt-pip \
  --sku Standard \
  --allocation-method Static \
  --version IPv4

# Wait for IP allocation and retrieve it
sleep 5
YOUR_PUBLIC_IP="$(az network public-ip show --resource-group "$RG" --name mgmt-pip --query ipAddress -o tsv)"

# Validate that we got a valid IP
if [[ -z "$YOUR_PUBLIC_IP" || "$YOUR_PUBLIC_IP" == "null" ]]; then
  echo "ERROR: Failed to retrieve public IP address.  Exiting."
  exit 1
fi

echo "  Public IP created: $YOUR_PUBLIC_IP"
echo ""

#-------------------------------------------------------------------------------
# Step 5 — Create NSG + Rules
#-------------------------------------------------------------------------------
echo "[Step 5] Creating NSG and security rules..."

az network nsg create --resource-group "$RG" --name "$NSG_NAME"

# Allow SSH only from your public IP (mgmt-pip)
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_NAME" \
  --name Allow-SSH \
  --protocol Tcp \
  --priority 1000 \
  --destination-port-ranges 22 \
  --access Allow \
  --direction Inbound \
  --source-address-prefixes "${YOUR_PUBLIC_IP}/32"

# Allow HTTP from the Internet
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_NAME" \
  --name Allow-HTTP \
  --protocol Tcp \
  --priority 1010 \
  --destination-port-ranges 80 \
  --access Allow \
  --direction Inbound \
  --source-address-prefixes Internet

# Allow HTTPS from the Internet
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_NAME" \
  --name Allow-HTTPS \
  --protocol Tcp \
  --priority 1020 \
  --destination-port-ranges 443 \
  --access Allow \
  --direction Inbound \
  --source-address-prefixes Internet
echo ""

#-------------------------------------------------------------------------------
# Step 6 — Create NICs
#-------------------------------------------------------------------------------
echo "[Step 6] Creating network interfaces..."

# sprt-nic (private only)
az network nic create \
  --resource-group "$RG" \
  --name sprt-nic \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --network-security-group "$NSG_NAME"

# mgmt-nic (with public IP)
az network nic create \
  --resource-group "$RG" \
  --name mgmt-nic \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --network-security-group "$NSG_NAME" \
  --public-ip-address mgmt-pip

# powr-nic (private only)
az network nic create \
  --resource-group "$RG" \
  --name powr-nic \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --network-security-group "$NSG_NAME"
echo ""

#-------------------------------------------------------------------------------
# Step 7 — Storage Account for Boot Diagnostics
#-------------------------------------------------------------------------------
echo "[Step 7] Creating storage account for boot diagnostics..."
echo "  Storage account name: $SA_NAME"

az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false

STORAGE_URI="$(az storage account show --resource-group "$RG" --name "$SA_NAME" --query "primaryEndpoints.blob" -o tsv)"
echo "  Storage URI: $STORAGE_URI"
echo ""

#-------------------------------------------------------------------------------
# Step 8 — Register Features (for ARM64 VM)
#-------------------------------------------------------------------------------
echo "[Step 8] Registering required features for ARM64 VM..."
az feature register --namespace Microsoft. Compute --name UseStandardSecurityType 2>/dev/null || true
az provider register --namespace Microsoft. Compute --wait 2>/dev/null || true
echo "  Feature registration completed."
echo ""

#-------------------------------------------------------------------------------
# Step 9 — VM Creation
#-------------------------------------------------------------------------------
echo "[Step 9] Creating virtual machines..."

# Get NIC IDs
SPR_NIC_ID="$(az network nic show --resource-group "$RG" --name sprt-nic --query id -o tsv)"
MGT_NIC_ID="$(az network nic show --resource-group "$RG" --name mgmt-nic --query id -o tsv)"
POW_NIC_ID="$(az network nic show --resource-group "$RG" --name powr-nic --query id -o tsv)"

# sprt-vm (Intel x64, Free Tier eligible with P6 Premium SSD 64GB)
echo "  Creating $VM1 (Standard_B1s, x64)..."
az vm create \
  --resource-group "$RG" \
  --name "$VM1" \
  --nics "$SPR_NIC_ID" \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Premium_LRS \
  --os-disk-size-gb 64 \
  --no-wait

# mgmt-vm (AMD x64, P6 Premium SSD 64GB, public IP)
echo "  Creating $VM2 (Standard_B2ats_v2, x64)..."
az vm create \
  --resource-group "$RG" \
  --name "$VM2" \
  --nics "$MGT_NIC_ID" \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B2ats_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Premium_LRS \
  --os-disk-size-gb 64 \
  --no-wait

# powr-vm (ARM64, cheapest Standard HDD 32GB)
echo "  Creating $VM3 (Standard_B2pts_v2, ARM64)..."
az vm create \
  --resource-group "$RG" \
  --name "$VM3" \
  --nics "$POW_NIC_ID" \
  --image Canonical:ubuntu-24_04-lts:server-arm64:latest \
  --size Standard_B2pts_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Standard_LRS \
  --os-disk-size-gb 32 \
  --security-type Standard

# Wait for all VMs to be created
echo "  Waiting for all VMs to be provisioned..."
az vm wait --resource-group "$RG" --name "$VM1" --created
az vm wait --resource-group "$RG" --name "$VM2" --created
echo "  All VMs created successfully."
echo ""

#-------------------------------------------------------------------------------
# Step 10 — Enable Boot Diagnostics
#-------------------------------------------------------------------------------
echo "[Step 10] Enabling boot diagnostics for all VMs..."
az vm boot-diagnostics enable --resource-group "$RG" --name "$VM1" --storage "$STORAGE_URI"
az vm boot-diagnostics enable --resource-group "$RG" --name "$VM2" --storage "$STORAGE_URI"
az vm boot-diagnostics enable --resource-group "$RG" --name "$VM3" --storage "$STORAGE_URI"
echo "  Boot diagnostics enabled."
echo ""

#-------------------------------------------------------------------------------
# Step 11 — Get Public IP (mgmt-vm only)
#-------------------------------------------------------------------------------
echo "[Step 11] Retrieving public IP for mgmt-vm..."
MGMT_PUBLIC_IP="$(az network public-ip show --resource-group "$RG" --name mgmt-pip --query ipAddress -o tsv)"
echo "  mgmt-vm Public IP: $MGMT_PUBLIC_IP"
echo ""

#-------------------------------------------------------------------------------
# Step 12 — Validation
#-------------------------------------------------------------------------------
echo "[Step 12] Validating resources..."
echo ""
echo "Virtual Machines:"
az vm list --resource-group "$RG" -o table
echo ""
echo "Network Interfaces:"
az network nic list --resource-group "$RG" -o table
echo ""
echo "NSG Rules:"
az network nsg rule list --resource-group "$RG" --nsg-name "$NSG_NAME" -o table
echo ""

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
echo "=============================================="
echo "Setup Complete!"
echo "=============================================="
echo ""
echo "Resources created:"
echo "  • Resource Group: $RG"
echo "  • VNet: $VNET_NAME (10.10.0. 0/16)"
echo "  • Subnet: $SUBNET_NAME (10. 10.1.0/24)"
echo "  • NSG: $NSG_NAME"
echo "  • Storage Account: $SA_NAME"
echo ""
echo "Virtual Machines:"
echo "  • $VM1 (Standard_B1s, Intel x64, 64GB P6 SSD)"
echo "  • $VM2 (Standard_B2ats_v2, AMD x64, 64GB P6 SSD) - Public IP: $MGMT_PUBLIC_IP"
echo "  • $VM3 (Standard_B2pts_v2, ARM64, 32GB S4 HDD)"
echo ""
echo "SSH Access (via mgmt-vm as jump host):"
echo "  ssh azureuser@$MGMT_PUBLIC_IP"
echo ""
echo "To access other VMs from mgmt-vm:"
echo "  ssh azureuser@<private-ip-of-sprt-vm-or-powr-vm>"
echo ""
echo "Estimated Monthly Cost: ~\$5-6/month"
echo "  • Public IP (Standard SKU): ~\$3.66/month"
echo "  • S4 32GB HDD disk: ~\$2/month"
echo "=============================================="
