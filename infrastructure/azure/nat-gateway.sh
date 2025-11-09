#!/bin/bash
# Script to create NAT Gateway for OpenShift Sandboxed Containers Peer Pods on Azure
# This provides outbound connectivity for peer pod VMs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Configuring NAT Gateway for Peer Pods ===${NC}"

# Get Azure resource group from cluster
AZURE_RESOURCE_GROUP=$(oc get infrastructure/cluster -o jsonpath='{.status.platformStatus.azure.resourceGroupName}')
echo -e "${YELLOW}Resource Group: ${AZURE_RESOURCE_GROUP}${NC}"

# Get Azure region
AZURE_REGION=$(az group show --resource-group ${AZURE_RESOURCE_GROUP} --query "{Location:location}" --output tsv)
echo -e "${YELLOW}Region: ${AZURE_REGION}${NC}"

# Get VNet name
AZURE_VNET_NAME=$(az network vnet list -g "${AZURE_RESOURCE_GROUP}" --query '[].name' -o tsv)
echo -e "${YELLOW}VNet: ${AZURE_VNET_NAME}${NC}"

# Get worker subnet ID
AZURE_SUBNET_ID=$(az network vnet subnet list \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --vnet-name "${AZURE_VNET_NAME}" \
  --query "[].{Id:id} | [? contains(Id, 'worker')]" \
  --output tsv)
echo -e "${YELLOW}Subnet ID: ${AZURE_SUBNET_ID}${NC}"

# NAT Gateway configuration
PEERPOD_NAT_GW="peerpod-nat-gw"
PEERPOD_NAT_GW_IP="peerpod-nat-gw-ip"

echo -e "${GREEN}Creating NAT Gateway components...${NC}"

# Check if NAT gateway already exists
if az network nat gateway show -g "${AZURE_RESOURCE_GROUP}" -n "${PEERPOD_NAT_GW}" &>/dev/null; then
  echo -e "${YELLOW}NAT Gateway ${PEERPOD_NAT_GW} already exists${NC}"
else
  # Create public IP
  echo -e "${YELLOW}Creating public IP: ${PEERPOD_NAT_GW_IP}${NC}"
  az network public-ip create \
    -g "${AZURE_RESOURCE_GROUP}" \
    -n "${PEERPOD_NAT_GW_IP}" \
    -l "${AZURE_REGION}" \
    --sku Standard

  # Create NAT gateway
  echo -e "${YELLOW}Creating NAT Gateway: ${PEERPOD_NAT_GW}${NC}"
  az network nat gateway create \
    -g "${AZURE_RESOURCE_GROUP}" \
    -l "${AZURE_REGION}" \
    --public-ip-addresses "${PEERPOD_NAT_GW_IP}" \
    -n "${PEERPOD_NAT_GW}"

  echo -e "${GREEN}✓ NAT Gateway created${NC}"
fi

# Attach NAT gateway to subnet
echo -e "${YELLOW}Attaching NAT Gateway to worker subnet...${NC}"
az network vnet subnet update \
  --nat-gateway "${PEERPOD_NAT_GW}" \
  --ids "${AZURE_SUBNET_ID}"

# Verify attachment
NAT_GW_ATTACHED=$(az network vnet subnet show --ids "${AZURE_SUBNET_ID}" --query "natGateway.id" -o tsv)

if [ -n "$NAT_GW_ATTACHED" ]; then
  echo -e "${GREEN}✓ NAT Gateway successfully attached to worker subnet${NC}"
  echo -e "${GREEN}  NAT Gateway ID: ${NAT_GW_ATTACHED}${NC}"
else
  echo -e "${RED}✗ Failed to attach NAT Gateway${NC}"
  exit 1
fi

# Get public IP address
PUBLIC_IP=$(az network public-ip show -g "${AZURE_RESOURCE_GROUP}" -n "${PEERPOD_NAT_GW_IP}" --query "ipAddress" -o tsv)
echo -e "${GREEN}✓ Peer pods will use public IP: ${PUBLIC_IP}${NC}"

echo -e "${GREEN}=== NAT Gateway configuration complete ===${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Create peer-pods ConfigMap with Azure credentials"
echo -e "  2. Create SSH key secret"
echo -e "  3. Apply KataConfig CR"
