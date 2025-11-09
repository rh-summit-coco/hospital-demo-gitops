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
