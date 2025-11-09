#!/bin/bash
# Script to create peer-pods ConfigMap with Azure resource IDs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Creating Peer Pods ConfigMap ===${NC}"

# Get Azure subscription ID
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${YELLOW}Subscription ID: ${AZURE_SUBSCRIPTION_ID}${NC}"

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

# Get NSG ID
AZURE_NSG_ID=$(az network nsg list --resource-group ${AZURE_RESOURCE_GROUP} --query "[].{Id:id}" --output tsv)
echo -e "${YELLOW}NSG ID: ${AZURE_NSG_ID}${NC}"

echo -e "${YELLOW}Creating peer-pods-cm ConfigMap...${NC}"

cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: peer-pods-cm
  namespace: openshift-sandboxed-containers-operator
data:
  CLOUD_PROVIDER: "azure"
  VXLAN_PORT: "9000"
  PROXY_TIMEOUT: "5m"
  AZURE_INSTANCE_SIZE: "Standard_D2s_v3"
  AZURE_INSTANCE_SIZES: "Standard_D2s_v3,Standard_D4s_v3"
  AZURE_SUBNET_ID: "${AZURE_SUBNET_ID}"
  AZURE_NSG_ID: "${AZURE_NSG_ID}"
  AZURE_IMAGE_ID: ""
  AZURE_REGION: "${AZURE_REGION}"
  AZURE_RESOURCE_GROUP: "${AZURE_RESOURCE_GROUP}"
  TAGS: "demo=summit,environment=dev"
  PEERPODS_LIMIT_PER_NODE: "10"
  ROOT_VOLUME_SIZE: "6"
  DISABLECVM: "true"
EOF

echo -e "${GREEN}✓ peer-pods-cm ConfigMap created${NC}"

echo -e "${GREEN}=== ConfigMap created successfully ===${NC}"
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Subscription: ${AZURE_SUBSCRIPTION_ID}"
echo -e "  Resource Group: ${AZURE_RESOURCE_GROUP}"
echo -e "  Region: ${AZURE_REGION}"
echo -e "  Subnet: ${AZURE_SUBNET_ID}"
