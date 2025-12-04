#!/bin/bash

#===============================================================================
# Azure Free Tier Minimal - Remove Public IP Script
# Run this AFTER Cloudflare Tunnel is working
#===============================================================================
#
# This script removes the temporary public IP to eliminate ongoing costs. 
# Only run this after you have verified the Cloudflare tunnel is working! 
#
# Savings: ~$3. 66/month → Final cost: ~$0/month
#
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Variables (must match the main setup script)
#-------------------------------------------------------------------------------
RG="free-tier-12mo-rg"
NSG_NAME="free-tier-nsg"

echo "=============================================="
echo "Azure Free Tier - Remove Public IP"
echo "=============================================="
echo ""

#-------------------------------------------------------------------------------
# Pre-flight check
#-------------------------------------------------------------------------------
echo "[Pre-flight] Verifying resources exist..."

# Check if public IP exists
if ! az network public-ip show --resource-group "$RG" --name mgmt-pip --query id -o tsv 2>/dev/null; then
  echo "  Public IP 'mgmt-pip' not found. It may have already been deleted."
  exit 0
fi

echo "  Public IP found.  Proceeding with removal."
echo ""

#-------------------------------------------------------------------------------
# Confirmation prompt
#-------------------------------------------------------------------------------
echo "WARNING: This will remove the public IP from mgmt-vm."
echo "Make sure Cloudflare Tunnel is working before proceeding!"
echo ""
read -p "Have you verified SSH access via Cloudflare Tunnel? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted. Please verify Cloudflare Tunnel is working first."
  echo ""
  echo "Test with: ssh azureuser@<your-cloudflare-domain>"
  exit 1
fi

echo ""

#-------------------------------------------------------------------------------
# Step 14a — Detach Public IP from NIC
#-------------------------------------------------------------------------------
echo "[Step 14a] Detaching public IP from mgmt-nic..."
az network nic ip-config update \
  --resource-group "$RG" \
  --name ipconfig1 \
  --nic-name mgmt-nic \
  --remove publicIpAddress

echo "  Public IP detached from NIC."
echo ""

#-------------------------------------------------------------------------------
# Step 14b — Delete Public IP Resource
#-------------------------------------------------------------------------------
echo "[Step 14b] Deleting public IP resource..."
az network public-ip delete \
  --resource-group "$RG" \
  --name mgmt-pip

echo "  Public IP deleted."
echo ""

#-------------------------------------------------------------------------------
# Step 14c — Update NSG to allow SSH from Cloudflare IPs
#-------------------------------------------------------------------------------
echo "[Step 14c] Updating NSG to allow SSH from Cloudflare IPs..."

# Cloudflare IPv4 ranges (as of 2024)
# Source: https://www. cloudflare.com/ips-v4
CLOUDFLARE_IPS="173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22"

az network nsg rule update \
  --resource-group "$RG" \
  --nsg-name "$NSG_NAME" \
  --name Allow-SSH \
  --source-address-prefixes $CLOUDFLARE_IPS

echo "  NSG updated to allow SSH from Cloudflare IPs only."
echo ""

#-------------------------------------------------------------------------------
# Validation
#-------------------------------------------------------------------------------
echo "[Validation] Verifying changes..."
echo ""
echo "Public IPs in resource group:"
az network public-ip list --resource-group "$RG" -o table
echo ""
echo "NSG SSH Rule:"
az network nsg rule show --resource-group "$RG" --nsg-name "$NSG_NAME" --name Allow-SSH --query "{name:name, sourceAddressPrefixes:sourceAddressPrefixes}" -o json
echo ""

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
echo "=============================================="
echo "Public IP Removal Complete!"
echo "=============================================="
echo ""
echo "Cost savings: ~\$3.66/month"
echo ""
echo "Access your VMs:"
echo "  • mgmt-vm: ssh azureuser@<your-cloudflare-domain>"
echo "  • Secondary VM: SSH from mgmt-vm to private IP"
echo ""
echo "To find private IPs:"
echo "  az vm list-ip-addresses --resource-group $RG -o table"
echo ""
echo "Final Monthly Cost: ~\$0/month (Free Tier only)"
echo "Annual Cost: ~\$0. 99 (one-time setup cost)"
echo ""
echo "=============================================="
