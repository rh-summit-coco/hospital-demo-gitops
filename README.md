# Hospital Demo GitOps Repository

This repository contains the GitOps manifests for the Hospital Demo application.

## Structure

```
environments/
  dev/
    deployment.yaml  - Application deployment
    service.yaml     - Service definition
    route.yaml       - OpenShift route
```

## How it works

1. The CI pipeline builds and signs the application image
2. The pipeline updates the `deployment.yaml` with the new signed image digest
3. ArgoCD detects the change and automatically deploys the new version
4. The deployment only succeeds if the image signature is valid

## Deployment Process

The deployment is managed by OpenShift GitOps (ArgoCD). When changes are pushed to this repository, ArgoCD automatically syncs the changes to the cluster.
