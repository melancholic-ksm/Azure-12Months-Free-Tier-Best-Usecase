#!/bin/bash

#===============================================================================
# Azure Free Tier 12-Month Plan (~$25 budget / ~$2 per month)
# With Cloudflare Tunnel Integration
#===============================================================================
#
# This plan is for users with a budget/credits ≤$25 for 12 months,
# or ≤$4 per month for 12 consecutive months and a domain name
# managed by Cloudflare DNS (which is free).
#
# This plan includes 3 VMs:
#   • B2ats v2 — 2 vCPUs, 1 GB RAM (AMD/x64)
#   • B2pts v2 — 2 vCPUs, 1 GB RAM (ARM64)
#   • B1s     — 1 vCPU, 1 GB RAM (Intel x64)
#
# All 3 VMs will run on the latest Ubuntu 24.04 LTS. 
#
# All VMs use P6 Premium free-tier 64 GB SSD OS disks.
#
# Cloudflare tunnel eliminates ongoing public IP costs after setup.
#
# Estimated costs:
#   • Public IP (temporary, 1-2 hrs setup): ~$0.01
#   • Final Monthly Cost: ~$2/month after public IP removal
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

# Cloudflare Tunnel configuration
# IMPORTANT: Replace with your actual domain/subdomain
CLOUDFLARE_DOMAIN="mgmt.example.com"
TUNNEL_NAME="azure-mgmt-tunnel"

echo "=============================================="
echo "Azure Free Tier 12-Month Setup Script"
echo "With Cloudflare Tunnel Integration"
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
# Step 4 — Public IP (temporary for setup only)
#-------------------------------------------------------------------------------
echo "[Step 4] Creating temporary public IP for mgmt-vm..."
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

echo "  Temporary Public IP created: $YOUR_PUBLIC_IP"
echo "  (This will be removed after Cloudflare tunnel setup)"
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

# mgmt-nic (with temporary public IP)
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
az feature register --namespace Microsoft.Compute --name UseStandardSecurityType 2>/dev/null || true
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

# mgmt-vm (AMD x64, P6 Premium SSD 64GB, temporary public IP)
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

# powr-vm (ARM64, P6 Premium SSD 64GB)
echo "  Creating $VM3 (Standard_B2pts_v2, ARM64)..."
az vm create \
  --resource-group "$RG" \
  --name "$VM3" \
  --nics "$POW_NIC_ID" \
  --image Canonical:ubuntu-24_04-lts:server-arm64:latest \
  --size Standard_B2pts_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --storage-sku Premium_LRS \
  --os-disk-size-gb 64 \
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
# Step 13 — Generate Cloudflare Tunnel Setup Script
#-------------------------------------------------------------------------------
echo "[Step 13] Generating Cloudflare Tunnel setup script..."

# Create a script to be run on mgmt-vm
cat > /tmp/cloudflare-tunnel-setup. sh << 'CLOUDFLARE_SCRIPT'
#!/bin/bash
#===============================================================================
# Cloudflare Tunnel Setup Script for mgmt-vm
# Run this script after SSHing into mgmt-vm
#===============================================================================

set -e

# Configuration - MODIFY THESE VALUES
CLOUDFLARE_DOMAIN="${CLOUDFLARE_DOMAIN:-mgmt.example.com}"
TUNNEL_NAME="${TUNNEL_NAME:-azure-mgmt-tunnel}"

echo "=============================================="
echo "Cloudflare Tunnel Setup"
echo "=============================================="
echo ""
echo "Domain: $CLOUDFLARE_DOMAIN"
echo "Tunnel: $TUNNEL_NAME"
echo ""

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  CLOUDFLARED_PKG="cloudflared-linux-amd64. deb"
elif [[ "$ARCH" == "aarch64" ]]; then
  CLOUDFLARED_PKG="cloudflared-linux-arm64.deb"
else
  echo "ERROR: Unsupported architecture: $ARCH"
  exit 1
fi

echo "[1/6] Installing cloudflared..."
wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/${CLOUDFLARED_PKG}" -O /tmp/cloudflared. deb
sudo dpkg -i /tmp/cloudflared. deb
rm /tmp/cloudflared.deb
echo "  cloudflared installed successfully."
echo ""

echo "[2/6] Logging in to Cloudflare..."
echo "  A browser window will open.  Select your domain to authorize."
cloudflared tunnel login
echo ""

echo "[3/6] Creating tunnel: $TUNNEL_NAME..."
cloudflared tunnel create "$TUNNEL_NAME"
echo ""

echo "[4/6] Creating configuration file..."
mkdir -p ~/.cloudflared

# Find the credentials file
CREDS_FILE=$(find ~/. cloudflared -name "*.json" -type f | head -1)
if [[ -z "$CREDS_FILE" ]]; then
  echo "ERROR: Credentials file not found.  Tunnel creation may have failed."
  exit 1
fi

cat > ~/.cloudflared/config.yml << EOF
tunnel: $TUNNEL_NAME
credentials-file: $CREDS_FILE

ingress:
  - hostname: $CLOUDFLARE_DOMAIN
    service: ssh://localhost:22
  - service: http_status:404
EOF

echo "  Configuration file created at ~/.cloudflared/config.yml"
echo ""

echo "[5/6] Routing tunnel through Cloudflare DNS..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$CLOUDFLARE_DOMAIN"
echo ""

echo "[6/6] Installing and starting cloudflared service..."
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
echo ""

echo "=============================================="
echo "Cloudflare Tunnel Setup Complete!"
echo "=============================================="
echo ""
echo "Your tunnel is now running and accessible at:"
echo "  ssh azureuser@$CLOUDFLARE_DOMAIN"
echo ""
echo "To verify tunnel status:"
echo "  sudo systemctl status cloudflared"
echo "  cloudflared tunnel list"
echo ""
echo "IMPORTANT: You can now remove the public IP from Azure"
echo "to eliminate ongoing costs (~\$3.66/month savings)."
echo ""
CLOUDFLARE_SCRIPT

chmod +x /tmp/cloudflare-tunnel-setup.sh
echo "  Cloudflare tunnel setup script generated."
echo ""

#-------------------------------------------------------------------------------
# Summary - Before Cloudflare Setup
#-------------------------------------------------------------------------------
echo "=============================================="
echo "Azure Infrastructure Setup Complete!"
echo "=============================================="
echo ""
echo "Resources created:"
echo "  • Resource Group: $RG"
echo "  • VNet: $VNET_NAME (10.10.0.0/16)"
echo "  • Subnet: $SUBNET_NAME (10.10.1. 0/24)"
echo "  • NSG: $NSG_NAME"
echo "  • Storage Account: $SA_NAME"
echo ""
echo "Virtual Machines:"
echo "  • $VM1 (Standard_B1s, Intel x64, 64GB P6 SSD)"
echo "  • $VM2 (Standard_B2ats_v2, AMD x64, 64GB P6 SSD) - Temp Public IP: $MGMT_PUBLIC_IP"
echo "  • $VM3 (Standard_B2pts_v2, ARM64, 64GB P6 SSD)"
echo ""
echo "=============================================="
echo "NEXT STEPS: Cloudflare Tunnel Setup"
echo "=============================================="
echo ""
echo "1.  SSH into mgmt-vm:"
echo "   ssh azureuser@$MGMT_PUBLIC_IP"
echo ""
echo "2. Copy and run the Cloudflare tunnel setup commands:"
echo ""
echo "   # Set your domain (replace with your actual domain)"
echo "   export CLOUDFLARE_DOMAIN=\"$CLOUDFLARE_DOMAIN\""
echo "   export TUNNEL_NAME=\"$TUNNEL_NAME\""
echo ""
echo "   # Install cloudflared"
echo "   wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64. deb -O /tmp/cloudflared.deb"
echo "   sudo dpkg -i /tmp/cloudflared.deb"
echo ""
echo "   # Login to Cloudflare (browser opens, select your domain)"
echo "   cloudflared tunnel login"
echo ""
echo "   # Create tunnel"
echo "   cloudflared tunnel create \$TUNNEL_NAME"
echo ""
echo "   # Create config file"
echo "   mkdir -p ~/. cloudflared"
echo "   CREDS_FILE=\$(find ~/.cloudflared -name \"*.json\" -type f | head -1)"
echo "   cat > ~/. cloudflared/config.yml << EOF"
echo "tunnel: \$TUNNEL_NAME"
echo "credentials-file: \$CREDS_FILE"
echo ""
echo "ingress:"
echo "  - hostname: \$CLOUDFLARE_DOMAIN"
echo "    service: ssh://localhost:22"
echo "  - service: http_status:404"
echo "EOF"
echo ""
echo "   # Route tunnel through Cloudflare DNS"
echo "   cloudflared tunnel route dns \$TUNNEL_NAME \$CLOUDFLARE_DOMAIN"
echo ""
echo "   # Install and start as service"
echo "   sudo cloudflared service install"
echo "   sudo systemctl start cloudflared"
echo "   sudo systemctl enable cloudflared"
echo ""
echo "3. Test the tunnel from your local machine:"
echo "   ssh azureuser@$CLOUDFLARE_DOMAIN"
echo ""
echo "4. Once tunnel works, run Step 14 to remove the public IP."
echo ""

#-------------------------------------------------------------------------------
# Create Step 14 script for removing public IP
#-------------------------------------------------------------------------------
echo "=============================================="
echo "Step 14 Command (Run after tunnel is working)"
echo "=============================================="
echo ""
echo "# Remove public IP to eliminate ongoing costs:"
echo ""
echo "# Detach PIP from NIC"
echo "az network nic ip-config update \\"
echo "  --resource-group \"$RG\" \\"
echo "  --name ipconfig1 \\"
echo "  --nic-name mgmt-nic \\"
echo "  --remove publicIpAddress"
echo ""
echo "# Delete the PIP resource"
echo "az network public-ip delete --resource-group \"$RG\" --name mgmt-pip"
echo ""
echo "# Update NSG to allow SSH from Cloudflare IPs instead"
echo "az network nsg rule update \\"
echo "  --resource-group \"$RG\" \\"
echo "  --nsg-name \"$NSG_NAME\" \\"
echo "  --name Allow-SSH \\"
echo "  --source-address-prefixes 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240. 0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0. 0/15 104.16.0.0/13 104.24.0. 0/14 172.64.0.0/13 131.0.72.0/22"
echo ""
echo "=============================================="
echo ""
