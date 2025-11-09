#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Generating GitOps manifests for ARO Summit Demo${NC}"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$BASE_DIR"

# Create all operator subscriptions
echo -e "${YELLOW}Creating operator subscriptions...${NC}"

# OpenShift GitOps
cat > operators/openshift-gitops/subscription.yaml <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# OpenShift Pipelines
cat > operators/openshift-pipelines/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-pipelines
  annotations:
    argocd.argoproj.io/sync-wave: "0"
EOF

cat > operators/openshift-pipelines/subscription.yaml <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Red Hat Developer Hub
cat > operators/rhdh/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: rhdh-operator
  annotations:
    argocd.argoproj.io/sync-wave: "0"
EOF

cat > operators/rhdh/operatorgroup.yaml <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhdh-operator-group
  namespace: rhdh-operator
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  targetNamespaces:
  - rhdh-operator
EOF

cat > operators/rhdh/subscription.yaml <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhdh
  namespace: rhdh-operator
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  channel: fast
  installPlanApproval: Automatic
  name: rhdh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# DevSpaces
cat > operators/devspaces/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: devspaces
  annotations:
    argocd.argoproj.io/sync-wave: "0"
EOF

cat > operators/devspaces/operatorgroup.yaml <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: devspaces-operator-group
  namespace: devspaces
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  targetNamespaces:
  - devspaces
EOF

cat > operators/devspaces/subscription.yaml <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: devspaces
  namespace: devspaces
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  channel: stable
  installPlanApproval: Automatic
  name: devspaces
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Advanced Cluster Management
cat > operators/acm/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: open-cluster-management
  annotations:
    argocd.argoproj.io/sync-wave: "0"
EOF

cat > operators/acm/operatorgroup.yaml <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: acm-operator-group
  namespace: open-cluster-management
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  targetNamespaces:
  - open-cluster-management
EOF

cat > operators/acm/subscription.yaml <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: advanced-cluster-management
  namespace: open-cluster-management
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  channel: release-2.12
  installPlanApproval: Automatic
  name: advanced-cluster-management
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

cat > operators/acm/multiclusterhub.yaml <<'EOF'
apiVersion: operator.open-cluster-management.io/v1
kind: MultiClusterHub
metadata:
  name: multiclusterhub
  namespace: open-cluster-management
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec: {}
EOF

# OpenShift Sandboxed Containers
cat > operators/sandboxed-containers/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-sandboxed-containers-operator
  annotations:
    argocd.argoproj.io/sync-wave: "0"
EOF

cat > operators/sandboxed-containers/operatorgroup.yaml <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: sandboxed-containers-operator-group
  namespace: openshift-sandboxed-containers-operator
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  targetNamespaces:
  - openshift-sandboxed-containers-operator
EOF

cat > operators/sandboxed-containers/subscription.yaml <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: sandboxed-containers-operator
  namespace: openshift-sandboxed-containers-operator
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  channel: stable
  installPlanApproval: Automatic
  name: sandboxed-containers-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: sandboxed-containers-operator.v1.10.3
EOF

cat > operators/sandboxed-containers/README.md <<'EOF'
# OpenShift Sandboxed Containers with Peer Pods on Azure

## Prerequisites

Before applying the KataConfig, you must:

1. Create the peer-pods ConfigMap with Azure credentials
2. Create the SSH key secret
3. Ensure NAT gateway is configured for worker subnet

## ConfigMaps and Secrets

The following resources must be created manually before applying the KataConfig:

### peer-pods-cm ConfigMap
Contains Azure configuration including:
- AZURE_SUBSCRIPTION_ID
- AZURE_REGION
- AZURE_RESOURCE_GROUP
- AZURE_SUBNET_ID
- etc.

### peer-pods-secret Secret
Contains Azure service principal credentials:
- AZURE_CLIENT_ID
- AZURE_CLIENT_SECRET
- AZURE_TENANT_ID

### ssh-key-secret Secret
Contains SSH keys for peer pod VMs (required by Azure API):
- id_rsa.pub
- id_rsa

## Azure Infrastructure

The NAT gateway must be created and attached to the worker subnet for peer pods to have outbound connectivity.

See: infrastructure/azure/nat-gateway.sh
EOF

echo -e "${GREEN}✓ Operator subscriptions created${NC}"

echo -e "${YELLOW}Creating Janine's development namespace...${NC}"

cat > infrastructure/namespaces/janine-app.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: janine-app
  labels:
    runtime: kata-remote
  annotations:
    argocd.argoproj.io/sync-wave: "0"
EOF

echo -e "${GREEN}✓ Namespaces created${NC}"

echo -e "${GREEN}All manifests generated successfully!${NC}"
