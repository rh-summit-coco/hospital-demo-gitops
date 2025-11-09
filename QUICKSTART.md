# Quick Start Guide - ARO Summit Demo

This guide will get you from zero to a fully deployed ARO platform in ~45 minutes.

## Prerequisites (5 minutes)

1. **ARO Cluster**: You have an ARO cluster running
   - Cluster: big-rock-v2 (or your own)
   - Console URL available
   - kubeadmin credentials

2. **Tools Installed**:
   ```bash
   oc version       # OpenShift CLI
   az version       # Azure CLI
   git --version    # Git
   ```

3. **Azure Access**:
   - Service Principal with Contributor role
   - Subscription ID
   - Resource Group access

## Fast Track Deployment (40 minutes)

### Step 1: Clone and Configure (2 minutes)

```bash
# Clone this repository
git clone https://github.com/<YOUR_USERNAME>/aro-gitops-demo.git
cd aro-gitops-demo

# Or fork it to your own GitHub account first (recommended)
```

### Step 2: Login to Cluster and Azure (3 minutes)

```bash
# Login to ARO
export KUBEADMIN_PASSWORD="et88A-y4Tjo-LjhGh-E5Z74"  # Your password
oc login https://api.uhfgfgde.eastus.aroapp.io:6443/ \
  -u kubeadmin \
  -p "$KUBEADMIN_PASSWORD"

# Verify login
oc whoami
oc get nodes

# Login to Azure
az login --service-principal \
  -u 122fdb1f-1b14-4b4b-8098-2f322f3d52d4 \
  -p "<AZURE_CLIENT_SECRET>" \
  --tenant 64dc69e4-d083-49fc-9569-ebece1dd1408

# Set subscription
az account set --subscription 1a84145c-974c-4237-9046-64a34c09752f
```

### Step 3: Run Automated Setup (35 minutes)

```bash
# Run the complete setup script
chmod +x automation/scripts/setup-all.sh
./automation/scripts/setup-all.sh
```

This script will:
1. ✅ Create NAT Gateway for peer pods (5 min)
2. ✅ Create all secrets and ConfigMaps (2 min)
3. ✅ Create Trustee operator secrets (1 min)
4. ✅ Deploy ArgoCD ApplicationSet (1 min)
5. ✅ Wait for operators to install (15-20 min)
6. ✅ Install Kata runtime (10-15 min)
7. ✅ Deploy Trustee KBS (5 min)

### Step 4: Monitor Progress

While the deployment runs, monitor in separate terminals:

```bash
# Terminal 1: Watch ArgoCD applications
watch oc get applications -n openshift-gitops

# Terminal 2: Monitor Kata installation
watch 'oc describe kataconfig | sed -n /^Status:/,/^Events/p'

# Terminal 3: Check operator pods
watch oc get pods -n openshift-sandboxed-containers-operator
```

### Step 5: Verify Deployment (5 minutes)

```bash
# Run verification script
chmod +x automation/scripts/verify-deployment.sh
./automation/scripts/verify-deployment.sh
```

## Test the Setup (5 minutes)

### Deploy Test Peer Pod

```bash
# Create a test peer pod
oc apply -f applications/demo/kata-hello-world.yaml

# Watch it start
oc get pod kata-hello-world -w

# Check logs (once Running)
oc logs kata-hello-world

# Verify Azure VM was created
az vm list --resource-group jfreiman-summit-rg | grep podvm
```

### Test ACM Policy

```bash
# This should FAIL (no runtime class)
oc run test-fail --image=busybox -n janine-app

# This should SUCCEED
oc run test-success --image=busybox \
  --overrides='{"spec":{"runtimeClassName":"kata-remote"}}' \
  -n janine-app
```

## Access UIs

### ArgoCD

```bash
# Get URL
oc get route openshift-gitops-server -n openshift-gitops \
  -o jsonpath='{.spec.host}'

# Get admin password
oc extract secret/openshift-gitops-cluster \
  -n openshift-gitops --to=-
```

### OpenShift Console

```
https://console-openshift-console.apps.uhfgfgde.eastus.aroapp.io/
Username: kubeadmin
Password: et88A-y4Tjo-LjhGh-E5Z74
```

## Troubleshooting

### Kata Installation Stuck?

```bash
# Check node status
oc get nodes

# Check machine config pool
oc get mcp kata-oc

# View detailed status
oc describe kataconfig cluster-kataconfig \
  -n openshift-sandboxed-containers-operator
```

### Peer Pod Not Starting?

```bash
# Check NAT gateway
AZURE_RESOURCE_GROUP=$(oc get infrastructure/cluster \
  -o jsonpath='{.status.platformStatus.azure.resourceGroupName}')
AZURE_VNET_NAME=$(az network vnet list \
  -g "${AZURE_RESOURCE_GROUP}" --query '[].name' -o tsv)
AZURE_SUBNET_ID=$(az network vnet subnet list \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --vnet-name "${AZURE_VNET_NAME}" \
  --query "[].{Id:id} | [? contains(Id, 'worker')]" \
  --output tsv)

az network vnet subnet show --ids "${AZURE_SUBNET_ID}" \
  --query "natGateway.id"

# Check CAA logs
oc logs -n openshift-sandboxed-containers-operator \
  ds/osc-caa-ds --tail=50
```

### ArgoCD Not Syncing?

```bash
# Force sync all applications
for app in $(oc get applications -n openshift-gitops -o name); do
  oc patch $app -n openshift-gitops \
    --type merge \
    -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
done
```

## What You Get

After successful deployment:

- ✅ **7 Operators** installed and configured
- ✅ **GitOps** managing everything via ArgoCD
- ✅ **Peer Pods** running on Azure VMs
- ✅ **ACM Policies** enforcing kata runtime
- ✅ **Trustee KBS** for confidential container attestation
- ✅ **Developer Platform** ready for Janine's team
- ✅ **Complete Documentation** for maintenance

## Next Steps

1. **Customize**: Edit manifests in Git, ArgoCD will sync
2. **Add Apps**: Create new applications in `applications/` directory
3. **Add Policies**: Create new ACM policies in `policies/acm/`
4. **Scale**: Adjust peer pod limits, instance types, etc.

## Support

- 📖 Full docs in `docs/` directory
- 🐛 Issues: Open GitHub issue
- 💬 Questions: Check Red Hat docs

**Deployment complete! 🎉**
