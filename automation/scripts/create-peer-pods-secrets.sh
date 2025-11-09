#!/bin/bash
# Script to create peer pods secrets for Azure
# These secrets are required for peer pods to create VMs in Azure

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Creating Peer Pods Secrets ===${NC}"

# Get Azure credentials from CLAUDE.md or environment
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-122fdb1f-1b14-4b4b-8098-2f322f3d52d4}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-X~~8Q~giDI2zrkTL-lZD0OJmXwL2GhM2lYvuiaCv}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-64dc69e4-d083-49fc-9569-ebece1dd1408}"

echo -e "${YELLOW}Creating peer-pods-secret...${NC}"

oc create secret generic peer-pods-secret \
  -n openshift-sandboxed-containers-operator \
  --from-literal=AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
  --from-literal=AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
  --from-literal=AZURE_TENANT_ID="${AZURE_TENANT_ID}" \
  --dry-run=client -o yaml | oc apply -f -

echo -e "${GREEN}✓ peer-pods-secret created${NC}"

# Generate SSH keys for peer pods
echo -e "${YELLOW}Generating SSH keys for peer pods...${NC}"

SSH_KEY_DIR="/tmp/peerpods-ssh-keys"
mkdir -p "$SSH_KEY_DIR"

if [ ! -f "$SSH_KEY_DIR/id_rsa" ]; then
  ssh-keygen -t rsa -b 2048 -f "$SSH_KEY_DIR/id_rsa" -N "" -C "peerpods@openshift"
  echo -e "${GREEN}✓ SSH keys generated${NC}"
else
  echo -e "${YELLOW}SSH keys already exist${NC}"
fi

echo -e "${YELLOW}Creating ssh-key-secret...${NC}"

oc create secret generic ssh-key-secret \
  -n openshift-sandboxed-containers-operator \
  --from-file=id_rsa.pub="$SSH_KEY_DIR/id_rsa.pub" \
  --from-file=id_rsa="$SSH_KEY_DIR/id_rsa" \
  --dry-run=client -o yaml | oc apply -f -

echo -e "${GREEN}✓ ssh-key-secret created${NC}"

# Clean up SSH keys
echo -e "${YELLOW}Cleaning up temporary SSH keys...${NC}"
shred --remove "$SSH_KEY_DIR/id_rsa" "$SSH_KEY_DIR/id_rsa.pub" 2>/dev/null || true
rmdir "$SSH_KEY_DIR" 2>/dev/null || true

echo -e "${GREEN}=== Secrets created successfully ===${NC}"
echo -e "${YELLOW}Next step: Create peer-pods-cm ConfigMap with Azure resource IDs${NC}"
