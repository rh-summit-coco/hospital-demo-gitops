# Dual Deployment: OpenShift + Azure RHEL VM

## Overview

This solution extends the existing ArgoCD deployment to deploy the **nodejs-ex** application to **two targets**:

1. **OpenShift Cluster** (existing) - Container in janine-dev namespace
2. **Azure RHEL VM** (new) - Same container running on standalone VM with podman

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Developer Workflow (Unchanged)                               │
└──────────────────────────────────────────────────────────────┘

Backstage → Git Push → Tekton Pipeline
                          ├─ Build Container
                          ├─ Push to OpenShift Registry
                          └─ Update Deployment Manifests

┌──────────────────────────────────────────────────────────────┐
│ ArgoCD Deployment (Extended to Two Targets)                 │
└──────────────────────────────────────────────────────────────┘

ArgoCD Detects Change
    ├─► Deploy to OpenShift (existing)
    │   └─ Namespace: janine-dev
    │      URL: https://nodejs-ex-janine-dev.apps.uhfgfgde.eastus.aroapp.io
    │
    └─► Deploy to Azure VM (NEW)
        └─ Triggers Job → Azure CLI → Create/Update VM
           URL: http://<VM-IP> (dynamic)
```

## How It Works

### 1. Container Build (Unchanged)
```
Tekton Pipeline:
  - Builds nodejs-ex container
  - Pushes to: image-registry.openshift-image-registry.svc:5000/janine-dev/nodejs-ex:latest
  - Exposed as: default-route-openshift-image-registry.apps.uhfgfgde.eastus.aroapp.io/janine-dev/nodejs-ex:latest
```

### 2. ArgoCD Syncs Two Deployments

**Deployment 1: OpenShift (Wave 4)**
```yaml
# Existing deployment in janine-dev namespace
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nodejs-ex
  namespace: janine-dev
spec:
  template:
    spec:
      containers:
      - image: image-registry.../janine-dev/nodejs-ex:latest
```

**Deployment 2: Azure VM (Wave 5)**
```yaml
# New: Job that creates/updates Azure VM
apiVersion: batch/v1
kind: Job
metadata:
  name: deploy-nodejs-ex-vm
  namespace: azure-infrastructure
spec:
  template:
    spec:
      containers:
      - name: azure-cli
        # Runs az vm create with cloud-init
```

### 3. VM Bootstrap (cloud-init)

When the VM is created, cloud-init:
1. Installs podman, nginx, firewalld
2. Creates systemd service: `/etc/systemd/system/nodejs-ex.service`
3. Pulls container from OpenShift registry
4. Starts container with podman
5. Configures nginx reverse proxy (port 80 → 8080)
6. Creates update script: `/usr/local/bin/update-nodejs-ex.sh`

The systemd service auto-starts on boot:
```bash
podman pull default-route-openshift-image-registry.../janine-dev/nodejs-ex:latest
podman run --name nodejs-ex -p 8080:8080 ...
```

### 4. Updates

When a new container is built:
- **OpenShift**: ArgoCD detects image change, rolling update
- **VM**: ArgoCD Job triggers `az vm run-command` → runs `/usr/local/bin/update-nodejs-ex.sh`
  - Pulls latest image
  - Restarts systemd service

## Files Created

```
aro-gitops-demo/
├── infrastructure/azure/
│   ├── nodejs-ex-vm-cloud-init.yaml      # Cloud-init template (reference)
│   ├── nodejs-ex-vm-deployment.yaml      # ArgoCD Job + ConfigMap
│   ├── setup-vm-deployment.sh            # Setup script
│   └── README-VM-DEPLOYMENT.md           # This file
│
└── applications/
    └── nodejs-ex-vm-deployment.yaml      # ArgoCD Application
```

## Deployment Instructions

### Prerequisites

1. OpenShift cluster with ArgoCD installed ✅
2. Tekton pipeline building nodejs-ex ✅
3. Azure CLI access with service principal ✅
4. SSH key for VM access

### Step 1: Setup

```bash
cd /Users/jfreiman/code/summit-demo/aro-gitops-demo/infrastructure/azure

# Run setup script (creates secrets, exposes registry)
./setup-vm-deployment.sh
```

This creates:
- `azure-infrastructure` namespace
- `azure-ssh-key` secret (for VM access)
- `azure-credentials` secret (for Azure CLI)
- Exposes OpenShift image registry route

### Step 2: Deploy ArgoCD Application

```bash
# Apply the ArgoCD Application
oc apply -f applications/nodejs-ex-vm-deployment.yaml

# Watch ArgoCD sync
oc get applications -n openshift-gitops nodejs-ex-vm -w

# Watch the Job
oc get job -n azure-infrastructure -w
```

### Step 3: Monitor Deployment

```bash
# Check Job logs
oc logs -n azure-infrastructure job/deploy-nodejs-ex-vm -f

# Expected output:
# === Logging in to Azure ===
# === Checking if VM exists ===
# VM doesn't exist - creating new VM
# === Creating Resource Group ===
# === Creating VM with cloud-init ===
# ============================================
# ✅ nodejs-ex VM deployed successfully!
# VM IP: 20.85.123.45
# Application URL: http://20.85.123.45
# ============================================
```

### Step 4: Verify Deployment

```bash
# Get VM IP
az vm show -d -g nodejs-ex-vm-rg -n nodejs-ex-rhel-vm --query publicIps -o tsv

# Test the application
VM_IP=<IP_FROM_ABOVE>
curl http://$VM_IP
curl http://$VM_IP:8080

# SSH to VM (optional)
ssh -i ~/.ssh/nodejs-ex-vm-key azureuser@$VM_IP

# On the VM, check status:
sudo systemctl status nodejs-ex.service
sudo podman ps
sudo podman logs nodejs-ex
```

## Testing Updates

### Trigger a Build

```bash
# Make a code change and push
cd <nodejs-ex-source-repo>
git commit -am "Test update"
git push

# Tekton pipeline runs automatically
oc get pipelinerun -n janine-dev -w
```

### Watch ArgoCD Deploy to Both Targets

```bash
# Terminal 1: Watch OpenShift deployment
oc get pods -n janine-dev -w

# Terminal 2: Watch VM update job
oc get job -n azure-infrastructure -w

# After sync completes, verify both:
# OpenShift:
curl https://nodejs-ex-janine-dev.apps.uhfgfgde.eastus.aroapp.io

# VM:
curl http://<VM-IP>
```

## How Image Pull Works

The VM needs to pull from the OpenShift internal registry. Two options:

### Option 1: Public Registry Route (Current)

```bash
# OpenShift exposes registry publicly
default-route-openshift-image-registry.apps.uhfgfgde.eastus.aroapp.io

# VM pulls with --tls-verify=false (self-signed cert)
podman pull --tls-verify=false \
  default-route-openshift-image-registry.apps.../janine-dev/nodejs-ex:latest
```

### Option 2: Service Account Token (More Secure)

```bash
# Create service account with image pull rights
oc create sa nodejs-ex-puller -n janine-dev
oc policy add-role-to-user system:image-puller \
  system:serviceaccount:janine-dev:nodejs-ex-puller

# Get token
TOKEN=$(oc create token nodejs-ex-puller -n janine-dev --duration=87600h)

# Create pull secret on VM
echo $TOKEN | base64 | podman login --username serviceaccount \
  --password-stdin \
  default-route-openshift-image-registry.apps...
```

## Cleanup

```bash
# Delete VM
az vm delete -g nodejs-ex-vm-rg -n nodejs-ex-rhel-vm --yes
az group delete -g nodejs-ex-vm-rg --yes

# Delete ArgoCD resources
oc delete application nodejs-ex-vm -n openshift-gitops
oc delete namespace azure-infrastructure
```

## Troubleshooting

### VM Creation Fails

```bash
# Check Job logs
oc logs -n azure-infrastructure job/deploy-nodejs-ex-vm

# Common issues:
# - Azure quota exceeded
# - SSH key not found
# - Network connectivity
```

### Container Not Starting on VM

```bash
# SSH to VM
ssh -i ~/.ssh/nodejs-ex-vm-key azureuser@<VM-IP>

# Check systemd service
sudo systemctl status nodejs-ex.service
sudo journalctl -u nodejs-ex.service -f

# Check podman
sudo podman ps -a
sudo podman logs nodejs-ex

# Common issues:
# - Image pull failed (registry not accessible)
# - Port 8080 already in use
# - Firewall blocking traffic
```

### Can't Access Application on VM

```bash
# Check if service is running
curl http://<VM-IP>:8080  # Direct to container

# If direct works but port 80 doesn't:
sudo systemctl status nginx
sudo firewall-cmd --list-all
```

### Updates Not Propagating to VM

```bash
# Check if Job ran
oc get job -n azure-infrastructure

# Manually trigger update
az vm run-command invoke \
  -g nodejs-ex-vm-rg \
  -n nodejs-ex-rhel-vm \
  --command-id RunShellScript \
  --scripts "/usr/local/bin/update-nodejs-ex.sh"
```

## Architecture Decisions

### Why Job Instead of Operator?

- **Simplicity**: Jobs are simpler than writing a custom operator
- **Idempotent**: Job checks if VM exists before creating
- **ArgoCD Native**: Works with ArgoCD hooks
- **Easy Debugging**: `oc logs job/...` is straightforward

### Why cloud-init?

- **Bootstrap Once**: VM self-configures on first boot
- **No Configuration Management**: No need for Ansible/Chef
- **Immutable**: VM configuration is defined in GitOps repo

### Why Not Crossplane?

- **Learning Curve**: Job-based approach is simpler
- **Dependencies**: No need for additional operators
- **Transparency**: Bash script is easy to understand and debug

Could migrate to Crossplane later if needed.

## Next Steps

1. **DNS**: Add Azure DNS zone for friendly URL (nodejs-ex-vm.example.com)
2. **TLS**: Add Let's Encrypt certificate to nginx
3. **Monitoring**: Export metrics from VM to OpenShift Prometheus
4. **HA**: Deploy multiple VMs behind Azure Load Balancer
5. **Auto-scaling**: Trigger VM scaling based on load

## Security Considerations

- ✅ Azure credentials stored in Secret
- ✅ SSH key stored in Secret
- ⚠️  Image registry uses self-signed cert (--tls-verify=false)
- ⚠️  VM runs container as root (podman rootful)
- 🔐 **For Production**: Use service account tokens, rootless podman, TLS

## Cost Estimate

**Azure RHEL VM (Standard_D2s_v3)**:
- Compute: ~$70/month (pay-as-you-go)
- Storage: ~$5/month (64GB Standard SSD)
- Network: ~$5/month (minimal egress)

**Total**: ~$80/month per VM

Compare to: OpenShift pod costs are already included in cluster subscription.
