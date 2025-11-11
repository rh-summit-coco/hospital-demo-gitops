# GitOps Pipeline Integration - Deployment Notes

## Summary

The secure-ci-pipeline has been fixed to implement **real GitOps integration**. Previously, the `update-gitops` task only printed fake success messages. Now it actually updates the GitOps repository and triggers ArgoCD deployment.

## What Was Fixed

### Issue
The pipeline's `update-gitops` task was completely fake:
- Only printed echo statements
- Never actually cloned the repository
- Never updated deployment files
- Never committed or pushed changes

### Solution
Implemented real Git operations in the pipeline:
1. Clones https://github.com/rh-summit-coco/hospital-demo-gitops.git
2. Updates `environments/dev/deployment.yaml` with new image tag
3. Commits with detailed metadata (image digest, source commit SHA)
4. Pushes to GitHub main branch
5. ArgoCD automatically detects and syncs changes

## Files in This Directory

### Permanent Storage (Saved from /tmp)
- `git-credentials-secret.yaml` - **SECRET** - Git authentication (excluded from Git)
- `secure-ci-pipeline-with-gitops.json` - Updated pipeline definition
- `test-pipelinerun.yaml` - Test configuration with all workspaces
- `README.md` - Usage documentation
- `DEPLOYMENT-NOTES.md` - This file

## Deployment Instructions

### 1. Deploy Git Credentials Secret (One-time setup)
```bash
~/bin/oc apply -f .pipeline-config/git-credentials-secret.yaml
```

### 2. Update Pipeline Definition
```bash
~/bin/oc apply -f .pipeline-config/secure-ci-pipeline-with-gitops.json
```

### 3. Run Test Pipeline
```bash
~/bin/oc create -f .pipeline-config/test-pipelinerun.yaml
```

### 4. Monitor Pipeline Progress
```bash
# Watch pipeline status
~/bin/oc get pipelinerun -n janine-dev -w

# Get logs from specific task
~/bin/oc logs -n janine-dev -l tekton.dev/pipelineTask=update-gitops -f
```

## Verification

### Check GitOps Update Succeeded
```bash
# View update-gitops task logs
POD=$(~/bin/oc get pod -n janine-dev -l tekton.dev/taskRun=<taskrun-name> --no-headers | awk '{print $1}')
~/bin/oc logs -n janine-dev $POD

# Verify deployment updated in cluster
~/bin/oc get deployment nodejs-ex -n janine-dev -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Check GitHub Repository
```bash
cd /Users/jfreiman/code/summit-demo/aro-gitops-demo
git pull origin main
git log --oneline -5
cat environments/dev/deployment.yaml
```

## Successful Test Results

### Test Pipeline Run: `secure-ci-test-real-gitops`
- **Status**: SUCCEEDED
- **Commit**: 9d0061b774bd5b28b8ed9366a7bec321f08f7ffd
- **Updated**: environments/dev/deployment.yaml
- **Change**: `test-1762872953` → `master`
- **Deployed**: Image updated in OpenShift cluster

### Evidence
```
To https://github.com/rh-summit-coco/hospital-demo-gitops.git
   01b18e6..9d0061b  main -> main

✅ GitOps repository updated successfully!
✅ ArgoCD will detect changes and sync within ~3 minutes
✅ New image: janine-dev/nodejs-ex:master
```

## Security Notes

- Git credentials secret contains GitHub token
- Token has push access to GitOps repository only
- Secret is excluded from Git via .gitignore
- Token can be rotated by updating secret
- Pipeline uses Kubernetes basic-auth workspace for credentials

## Pipeline Task Dependencies

The update-gitops task runs after these tasks complete:
1. clone-source
2. source-security-scan
3. add-dockerfile
4. build-container
5. vulnerability-scan
6. sign-image
7. register-pcr-values
8. seal-secret
9. generate-sbom
10. **update-gitops** ← Real GitOps update happens here

## Troubleshooting

### Pipeline Fails at update-gitops
Check task logs:
```bash
~/bin/oc get taskrun -n janine-dev | grep update-gitops
~/bin/oc logs -n janine-dev <taskrun-pod-name>
```

### Git Credentials Not Working
Verify secret exists and has correct format:
```bash
~/bin/oc get secret git-credentials -n janine-dev -o yaml
```

### ArgoCD Not Syncing
Check ArgoCD application status (if ArgoCD app is configured):
```bash
~/bin/oc get application -n openshift-gitops
```

## Related Files

- Pipeline definition in cluster: `~/bin/oc get pipeline secure-ci-pipeline -n janine-dev`
- GitOps repository: https://github.com/rh-summit-coco/hospital-demo-gitops
- Deployment manifest: `environments/dev/deployment.yaml`
