# Pipeline Configuration Files

This directory contains the configuration files for the secure CI/CD pipeline with GitOps integration.

## Files

### git-credentials-secret.yaml
**IMPORTANT: Contains sensitive GitHub token - DO NOT commit to Git!**

Kubernetes Secret for Git authentication used by the pipeline to push updates to the GitOps repository.

To apply:
```bash
~/bin/oc apply -f git-credentials-secret.yaml
```

### secure-ci-pipeline-with-gitops.json
Updated pipeline definition with real GitOps integration that:
- Clones the GitOps repository
- Updates deployment manifests with new image tags
- Commits and pushes changes to GitHub
- Triggers ArgoCD sync

To apply:
```bash
~/bin/oc apply -f secure-ci-pipeline-with-gitops.json
```

### test-pipelinerun.yaml
Test PipelineRun configuration that includes all required workspaces:
- source-ws: Source code workspace
- dockerconfig-ws: Docker registry credentials
- git-credentials-ws: Git credentials for GitOps updates

To run a test:
```bash
~/bin/oc create -f test-pipelinerun.yaml
```

## GitOps Update Flow

The pipeline performs the following GitOps operations:

1. **Clone**: Clones https://github.com/rh-summit-coco/hospital-demo-gitops.git
2. **Update**: Modifies `environments/dev/deployment.yaml` with new image tag
3. **Commit**: Creates commit with image digest and source commit SHA
4. **Push**: Pushes to GitHub main branch
5. **ArgoCD**: Automatically detects changes and syncs deployment

## Security Notes

- The git-credentials-secret.yaml file is excluded from Git via .gitignore
- GitHub token should have minimal permissions (only push to GitOps repo)
- Token can be rotated by updating the secret and restarting pipeline runs
