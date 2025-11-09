# Quick Start: Dual Deployment (OpenShift + VM)

Deploy nodejs-ex to **both** OpenShift and Azure RHEL VM simultaneously via ArgoCD.

## Current State

✅ **OpenShift Deployment** (Working)
- URL: https://nodejs-ex-janine-dev.apps.uhfgfgde.eastus.aroapp.io
- Namespace: janine-dev
- Managed by: ArgoCD (existing)

➕ **Azure VM Deployment** (NEW - To Be Deployed)
- URL: http://\<VM-IP\> (dynamic)
- Location: Azure East US
- Managed by: ArgoCD Job

## Architecture

```
Git Push
   ↓
Tekton Pipeline (Builds Container)
   ↓
OpenShift Registry
   ├─► ArgoCD → OpenShift Deployment (janine-dev)
   └─► ArgoCD → Azure VM Job → RHEL VM with podman
```

## One-Command Deployment

```bash
cd /Users/jfreiman/code/summit-demo/aro-gitops-demo

# Step 1: Setup prerequisites
./infrastructure/azure/setup-vm-deployment.sh

# Step 2: Deploy ArgoCD Application
oc apply -f applications/nodejs-ex-vm-deployment.yaml

# Step 3: Watch deployment
oc get job -n azure-infrastructure -w
```

## Detailed Steps

### 1. Setup

```bash
# Create namespace and secrets
cd infrastructure/azure
./setup-vm-deployment.sh

# This creates:
# - azure-infrastructure namespace
# - SSH key for VM access
# - Exposes OpenShift image registry
```

### 2. Deploy

```bash
# Apply ArgoCD Application
oc apply -f applications/nodejs-ex-vm-deployment.yaml

# ArgoCD will:
# 1. Create azure-infrastructure namespace
# 2. Create azure-credentials secret
# 3. Create cloud-init ConfigMap
# 4. Run Job to deploy VM
```

### 3. Monitor

```bash
# Watch ArgoCD Application
oc get application nodejs-ex-vm -n openshift-gitops

# Watch Job execution
oc get job -n azure-infrastructure

# View Job logs
oc logs -n azure-infrastructure job/deploy-nodejs-ex-vm -f
```

### 4. Get VM IP

```bash
# Login to Azure
az login --service-principal -u <AZURE_CLIENT_ID> -p <AZURE_CLIENT_SECRET> --tenant <AZURE_TENANT_ID>
  -u 122fdb1f-1b14-4b4b-8098-2f322f3d52d4 \
  -p <AZURE_CLIENT_SECRET> \
  --tenant 64dc69e4-d083-49fc-9569-ebece1dd1408

az account set --subscription 1a84145c-974c-4237-9046-64a34c09752f

# Get VM IP
VM_IP=$(az vm show -d \
  -g nodejs-ex-vm-rg \
  -n nodejs-ex-rhel-vm \
  --query publicIps -o tsv)

echo "VM IP: $VM_IP"
```

### 5. Test Both Deployments

```bash
# Test OpenShift deployment
curl https://nodejs-ex-janine-dev.apps.uhfgfgde.eastus.aroapp.io

# Test VM deployment
curl http://$VM_IP
curl http://$VM_IP:8080  # Direct to container
```

## What Gets Deployed

### On OpenShift (Existing)
```
janine-dev namespace
└── nodejs-ex deployment
    ├── Image: image-registry.../janine-dev/nodejs-ex:latest
    ├── Port: 8080
    └── Route: nodejs-ex-janine-dev.apps.uhfgfgde.eastus.aroapp.io
```

### On Azure VM (New)
```
Azure Resource Group: nodejs-ex-vm-rg
└── RHEL 9 VM: nodejs-ex-rhel-vm
    ├── Size: Standard_D2s_v3 (2 vCPU, 8GB RAM)
    ├── OS: Red Hat Enterprise Linux 9.4
    ├── Podman: Runs same container image
    ├── Systemd: Auto-starts on boot
    ├── Nginx: Reverse proxy (80 → 8080)
    └── Public IP: Dynamic
```

## How Updates Work

When you push code changes:

```
Git Push
   ↓
Tekton builds new image → Pushes to registry
   ↓
ArgoCD detects image change
   ├─► OpenShift: Rolling update (automatic)
   └─► VM: Job triggers SSH update command (automatic)
```

The VM update:
```bash
# ArgoCD Job runs:
az vm run-command invoke \
  -g nodejs-ex-vm-rg \
  -n nodejs-ex-rhel-vm \
  --command-id RunShellScript \
  --scripts "/usr/local/bin/update-nodejs-ex.sh"

# On the VM, this script runs:
podman pull .../janine-dev/nodejs-ex:latest
systemctl restart nodejs-ex.service
```

## Verification

### Check OpenShift Deployment

```bash
oc get deployment -n janine-dev nodejs-ex
oc get pods -n janine-dev
oc logs -n janine-dev deployment/nodejs-ex
```

### Check VM Deployment

```bash
# SSH to VM
ssh -i ~/.ssh/nodejs-ex-vm-key azureuser@$VM_IP

# On VM:
sudo systemctl status nodejs-ex.service
sudo podman ps
sudo podman logs nodejs-ex
curl localhost:8080
```

## Troubleshooting

### Job Fails

```bash
# Check logs
oc logs -n azure-infrastructure job/deploy-nodejs-ex-vm

# Common issues:
# - Azure quota exceeded → Request quota increase
# - SSH key not found → Run setup-vm-deployment.sh
# - Network timeout → Check Azure connectivity
```

### VM Created But App Not Running

```bash
# SSH to VM
ssh -i ~/.ssh/nodejs-ex-vm-key azureuser@$VM_IP

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log

# Check systemd service
sudo systemctl status nodejs-ex.service
sudo journalctl -u nodejs-ex.service -f
```

### Can't Pull Image from Registry

```bash
# On VM, test image pull manually
sudo podman pull --tls-verify=false \
  default-route-openshift-image-registry.apps.uhfgfgde.eastus.aroapp.io/janine-dev/nodejs-ex:latest

# If fails, check registry is exposed
oc get route -n openshift-image-registry

# Should show:
# default-route   default-route-openshift-image-registry.apps...
```

## Cleanup

```bash
# Delete VM
az vm delete -g nodejs-ex-vm-rg -n nodejs-ex-rhel-vm --yes
az group delete -g nodejs-ex-vm-rg --yes

# Delete ArgoCD Application
oc delete application nodejs-ex-vm -n openshift-gitops

# Delete namespace
oc delete namespace azure-infrastructure
```

## Next Steps

After successful deployment:

1. **Add DNS**: Create Azure DNS zone for friendly URL
2. **Add TLS**: Configure Let's Encrypt on nginx
3. **Monitoring**: Export metrics to Prometheus
4. **HA**: Add load balancer with multiple VMs
5. **Auto-scale**: Use Azure VMSS for scaling

## Files Reference

```
aro-gitops-demo/
├── infrastructure/azure/
│   ├── nodejs-ex-vm-deployment.yaml      # Main Job manifest
│   ├── setup-vm-deployment.sh            # Setup script
│   └── README-VM-DEPLOYMENT.md           # Full docs
├── applications/
│   └── nodejs-ex-vm-deployment.yaml      # ArgoCD Application
└── DUAL-DEPLOYMENT-QUICKSTART.md         # This file
```

## Summary

You now have **one application deployed to two targets**:

| Target | URL | Management | Purpose |
|--------|-----|------------|---------|
| OpenShift | https://nodejs-ex-janine-dev.apps... | ArgoCD | Production K8s workload |
| Azure VM | http://\<VM-IP\> | ArgoCD Job | Traditional VM deployment |

Both are **automatically updated** when you push code changes. ArgoCD manages both deployments from the same GitOps repository.
