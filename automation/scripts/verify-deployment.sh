#!/bin/bash
# Verification script for ARO Summit Demo deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

check() {
    local description=$1
    local command=$2

    echo -n "Checking: $description... "

    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((FAILED++))
        return 1
    fi
}

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ARO Summit Demo - Deployment Verification${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"

# Cluster connectivity
echo -e "${YELLOW}=== Cluster Connectivity ===${NC}"
check "OpenShift cluster login" "oc whoami"
check "Cluster API accessible" "oc get clusterversion"

# Operators
echo -e "\n${YELLOW}=== Operators ===${NC}"
check "GitOps operator installed" "oc get operators.operators.coreos.com openshift-gitops-operator.openshift-operators"
check "Pipelines operator installed" "oc get operators.operators.coreos.com openshift-pipelines-operator-rh.openshift-operators"
check "RHDH operator installed" "oc get operators.operators.coreos.com rhdh.rhdh-operator"
check "DevSpaces operator installed" "oc get operators.operators.coreos.com devspaces.devspaces"
check "ACM operator installed" "oc get operators.operators.coreos.com advanced-cluster-management.open-cluster-management"
check "Sandboxed Containers operator installed" "oc get operators.operators.coreos.com sandboxed-containers-operator.openshift-sandboxed-containers-op"
check "Trustee operator installed" "oc get operators.operators.coreos.com trustee-operator.trustee-operator-system"

# ACM
echo -e "\n${YELLOW}=== Advanced Cluster Management ===${NC}"
check "MultiClusterHub exists" "oc get multiclusterhub multiclusterhub -n open-cluster-management"
check "MultiClusterHub running" "oc get multiclusterhub multiclusterhub -n open-cluster-management -o jsonpath='{.status.phase}' | grep -q Running"
check "Gatekeeper installed" "oc get crd constrainttemplates.templates.gatekeeper.sh"

# Kata/Peer Pods
echo -e "\n${YELLOW}=== OpenShift Sandboxed Containers ===${NC}"
check "KataConfig exists" "oc get kataconfig cluster-kataconfig -n openshift-sandboxed-containers-operator"
check "Kata runtime class exists" "oc get runtimeclass kata-remote"
check "CAA daemon set exists" "oc get ds osc-caa-ds -n openshift-sandboxed-containers-operator"
check "peer-pods-cm ConfigMap exists" "oc get cm peer-pods-cm -n openshift-sandboxed-containers-operator"
check "peer-pods-secret exists" "oc get secret peer-pods-secret -n openshift-sandboxed-containers-operator"
check "ssh-key-secret exists" "oc get secret ssh-key-secret -n openshift-sandboxed-containers-operator"

# Check if kata is fully installed
KATA_READY=$(oc get kataconfig cluster-kataconfig -n openshift-sandboxed-containers-operator -o jsonpath='{.status.runtimeClass}' 2>/dev/null || echo "")
if [ "$KATA_READY" = "kata-remote" ]; then
    echo -e "${GREEN}✓ Kata installation complete${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ Kata installation in progress${NC}"
fi

# ACM Policies
echo -e "\n${YELLOW}=== ACM Policies ===${NC}"
check "Kata runtime policy exists" "oc get policy policy-kata-runtime-janine -n open-cluster-management"
check "Gatekeeper constraint exists" "oc get k8srequiredruntimeclass janine-app-kata-runtime"

# Trustee / Key Broker Service
echo -e "\n${YELLOW}=== Red Hat build of Trustee ===${NC}"
check "KbsConfig exists" "oc get kbsconfig kbsconfig -n trustee-operator-system"
check "KBS deployment exists" "oc get deployment kbs -n trustee-operator-system"
check "KBS service exists" "oc get service kbs-service -n trustee-operator-system"
check "KBS HTTPS certificate secret exists" "oc get secret kbs-https-certificate -n trustee-operator-system"
check "KBS authentication secret exists" "oc get secret kbs-auth-public-key -n trustee-operator-system"

# Namespaces
echo -e "\n${YELLOW}=== Namespaces ===${NC}"
check "janine-app namespace exists" "oc get namespace janine-app"

# Azure Infrastructure
echo -e "\n${YELLOW}=== Azure Infrastructure ===${NC}"
if command -v az &> /dev/null; then
    AZURE_RESOURCE_GROUP=$(oc get infrastructure/cluster -o jsonpath='{.status.platformStatus.azure.resourceGroupName}' 2>/dev/null || echo "")
    if [ -n "$AZURE_RESOURCE_GROUP" ]; then
        AZURE_VNET_NAME=$(az network vnet list -g "${AZURE_RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
        if [ -n "$AZURE_VNET_NAME" ]; then
            AZURE_SUBNET_ID=$(az network vnet subnet list --resource-group "${AZURE_RESOURCE_GROUP}" --vnet-name "${AZURE_VNET_NAME}" --query "[].{Id:id} | [? contains(Id, 'worker')]" --output tsv 2>/dev/null || echo "")
            if [ -n "$AZURE_SUBNET_ID" ]; then
                check "NAT Gateway attached to subnet" "az network vnet subnet show --ids '${AZURE_SUBNET_ID}' --query 'natGateway.id' -o tsv | grep -q nat"
            fi
        fi
    fi
fi

# Test Peer Pod (if kata-hello-world exists)
echo -e "\n${YELLOW}=== Test Workloads ===${NC}"
if oc get pod kata-hello-world -n default &>/dev/null; then
    check "kata-hello-world pod exists" "oc get pod kata-hello-world -n default"
    POD_STATUS=$(oc get pod kata-hello-world -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$POD_STATUS" = "Running" ]; then
        echo -e "${GREEN}✓ kata-hello-world pod is Running${NC}"
        ((PASSED++))

        # Check if it's actually a peer pod (has Azure VM)
        check "Peer pod VM created in Azure" "az vm list --resource-group ${AZURE_RESOURCE_GROUP} --query \"[?contains(name, 'podvm')]\" -o tsv | grep -q podvm"
    else
        echo -e "${YELLOW}⚠ kata-hello-world pod status: ${POD_STATUS}${NC}"
    fi
fi

# Summary
echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Verification Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Passed: ${PASSED}${NC}"
echo -e "${RED}  Failed: ${FAILED}${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ All checks passed!${NC}"
    exit 0
else
    echo -e "\n${YELLOW}⚠ Some checks failed. Review the output above.${NC}"
    exit 1
fi
