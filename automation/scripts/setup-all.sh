#!/bin/bash
# Master setup script for ARO Summit Demo
# This script orchestrates the complete deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     ARO Summit Demo - Complete Platform Deployment           ║
║                                                               ║
║  Components:                                                  ║
║   • OpenShift GitOps (ArgoCD)                                 ║
║   • OpenShift Pipelines (Tekton)                              ║
║   • Red Hat Developer Hub (Backstage)                         ║
║   • DevSpaces                                                 ║
║   • Advanced Cluster Management (ACM)                         ║
║   • OpenShift Sandboxed Containers (Kata + Peer Pods)         ║
║   • Red Hat build of Trustee (Confidential Containers)        ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v oc &> /dev/null; then
    echo -e "${RED}✗ oc CLI not found. Please install OpenShift CLI${NC}"
    exit 1
fi

if ! command -v az &> /dev/null; then
    echo -e "${RED}✗ Azure CLI not found. Please install Azure CLI${NC}"
    exit 1
fi

# Check cluster connectivity
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged in to OpenShift cluster${NC}"
    exit 1
fi

CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
echo -e "${GREEN}✓ Connected to cluster: ${CLUSTER_NAME}${NC}"

# Phase 1: Azure Infrastructure
echo -e "\n${BLUE}═══ Phase 1: Azure Infrastructure ===${NC}"
echo -e "${YELLOW}Setting up NAT Gateway for peer pods...${NC}"

if [ -f "$BASE_DIR/infrastructure/azure/nat-gateway.sh" ]; then
    chmod +x "$BASE_DIR/infrastructure/azure/nat-gateway.sh"
    "$BASE_DIR/infrastructure/azure/nat-gateway.sh"
else
    echo -e "${YELLOW}⚠ NAT Gateway script not found, skipping...${NC}"
fi

# Phase 2: Secrets and ConfigMaps
echo -e "\n${BLUE}═══ Phase 2: Creating Secrets and ConfigMaps ===${NC}"

echo -e "${YELLOW}Creating peer pods secrets...${NC}"
if [ -f "$SCRIPT_DIR/create-peer-pods-secrets.sh" ]; then
    chmod +x "$SCRIPT_DIR/create-peer-pods-secrets.sh"
    "$SCRIPT_DIR/create-peer-pods-secrets.sh"
fi

echo -e "${YELLOW}Creating peer pods ConfigMap...${NC}"
if [ -f "$SCRIPT_DIR/create-peer-pods-configmap.sh" ]; then
    chmod +x "$SCRIPT_DIR/create-peer-pods-configmap.sh"
    "$SCRIPT_DIR/create-peer-pods-configmap.sh"
fi

echo -e "${YELLOW}Creating Trustee operator secrets...${NC}"
if [ -f "$SCRIPT_DIR/create-trustee-secrets.sh" ]; then
    chmod +x "$SCRIPT_DIR/create-trustee-secrets.sh"
    "$SCRIPT_DIR/create-trustee-secrets.sh"
fi

# Phase 3: GitOps Deployment
echo -e "\n${BLUE}═══ Phase 3: GitOps Deployment ===${NC}"

read -p "Have you pushed this repository to GitHub and updated the repoURL in bootstrap/argocd/applicationset.yaml? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Please push to GitHub and update the repoURL first, then re-run this script${NC}"
    exit 1
fi

echo -e "${YELLOW}Deploying GitOps ApplicationSet...${NC}"

# Ensure GitOps operator is ready
echo -e "${YELLOW}Waiting for OpenShift GitOps to be ready...${NC}"
oc wait --for=condition=Available --timeout=600s deployment/openshift-gitops-server -n openshift-gitops 2>/dev/null || echo "GitOps not yet installed, will be installed by ApplicationSet"

# Apply ApplicationSet
echo -e "${YELLOW}Applying ApplicationSet...${NC}"
oc apply -f "$BASE_DIR/bootstrap/argocd/applicationset.yaml"

echo -e "${GREEN}✓ ApplicationSet deployed${NC}"

# Phase 4: Monitor Deployment
echo -e "\n${BLUE}═══ Phase 4: Monitoring Deployment ===${NC}"

echo -e "${YELLOW}You can monitor the deployment in the ArgoCD UI:${NC}"
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "Route not yet available")
echo -e "${GREEN}  ArgoCD URL: https://${ARGOCD_ROUTE}${NC}"

echo -e "\n${YELLOW}Or watch ArgoCD applications:${NC}"
echo -e "${GREEN}  oc get applications -n openshift-gitops -w${NC}"

echo -e "\n${YELLOW}Monitor Kata installation:${NC}"
echo -e "${GREEN}  watch 'oc describe kataconfig | sed -n /^Status:/,/^Events/p'${NC}"

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Setup initiated successfully!${NC}"
echo -e "${YELLOW}The platform will be deployed via GitOps.${NC}"
echo -e "${YELLOW}This may take 30-60 minutes for complete deployment.${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
