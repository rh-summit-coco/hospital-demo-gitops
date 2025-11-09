# Red Hat build of Trustee Operator

This directory contains the configuration for the Red Hat build of Trustee operator, which provides attestation and key management services for confidential containers on Azure.

## Components

### Operator Installation

- **namespace.yaml**: Creates the `trustee-operator-system` namespace
- **operatorgroup.yaml**: Creates the OperatorGroup for the Trustee operator
- **subscription.yaml**: Subscribes to the `trustee-operator` from Red Hat operators catalog (version 0.4.2)

### Configuration

- **kbs-config-cm.yaml**: Key Broker Service configuration
  - Defines KBS socket and authentication settings
  - Configures attestation token type (CoCo)
  - Sets up local filesystem repository for secrets
  - Configures Attestation Service with OPA policy engine
  - Sets up RVPS (Reference Value Provider Service) with local JSON storage

- **rvps-reference-values.yaml**: Reference values for attestation validation
  - Initially empty JSON array
  - Must be populated with PCR values and container image digests
  - See `docs/06-trustee-attestation.md` for details

### Policies

- **attestation-policy.yaml**: OPA policy for Azure vTPM SNP attestation
  - Validates TEE type (`azsnpvtpm`)
  - Verifies Platform Configuration Registers (PCRs 03, 08, 09, 11, 12)
  - Validates container image signatures and digests
  - Policy written in Rego language

- **security-policy.yaml**: Container image signature verification
  - Enforces signed images from trusted registries
  - Configures GPG key paths for signature verification
  - Supports quay.io and Red Hat registries

- **resource-policy.yaml**: Resource access control policy
  - Controls access to encryption keys, configuration, and certificates
  - Enforces TCB (Trusted Computing Base) status validation
  - Requires workload attestation before granting access

### Custom Resources

- **kbsconfig.yaml**: KbsConfig custom resource
  - References all ConfigMaps and Secrets
  - Deploys KBS in AllInOneDeployment mode (KBS + AS + RVPS)
  - Configures service type as ClusterIP
  - Uses default Red Hat KBS image

## Secrets

The following secrets must be created before deploying the KbsConfig:

1. **kbs-https-certificate**: TLS certificate for KBS HTTPS endpoint
2. **kbs-https-key**: TLS private key for KBS HTTPS endpoint
3. **kbs-attestation-token**: Token for attestation requests
4. **kbs-auth-public-key**: Public key for JWT authentication

These secrets are created automatically by the setup script:
```bash
automation/scripts/create-trustee-secrets.sh
```

## Deployment Order (Sync Waves)

1. **Wave 0**: Namespace creation
2. **Wave 1**: OperatorGroup and Subscription
3. **Wave 2**: ConfigMaps (configuration and policies)
4. **Wave 3**: KbsConfig CR (after operator is ready)

## Azure-Specific Configuration

### vTPM SNP Attestation

The attestation policy is specifically configured for Azure confidential VMs using vTPM (Virtual Trusted Platform Module) with SNP (Secure Nested Paging):

- **TEE Type**: `azsnpvtpm`
- **Critical PCRs**:
  - PCR 03: Firmware and UEFI boot
  - PCR 08: Kernel command line
  - PCR 09: Kernel image and initrd
  - PCR 11: Boot configuration
  - PCR 12: Kernel command line and initrd

### PCR Value Collection

To populate reference values:

```bash
# From a trusted peer pod
oc exec -it <trusted-pod> -- cat /sys/kernel/security/tpm0/binary_bios_measurements

# Update RVPS ConfigMap
oc edit configmap rvps-reference-values -n trustee-operator-system
```

## Verification

After deployment, verify the installation:

```bash
# Check operator
oc get operators.operators.coreos.com trustee-operator.trustee-operator-system

# Check KbsConfig
oc get kbsconfig kbsconfig -n trustee-operator-system

# Check KBS deployment
oc get deployment kbs -n trustee-operator-system

# Check KBS service
oc get service kbs-service -n trustee-operator-system

# Check KBS pods
oc get pods -n trustee-operator-system -l app=kbs

# View KBS logs
oc logs -n trustee-operator-system deployment/kbs
```

## Configuration Updates

To update policies or configuration:

1. Edit the appropriate YAML file in this directory
2. Commit and push to Git
3. ArgoCD will automatically sync the changes
4. KBS pods may need to be restarted to pick up new configuration

```bash
# Restart KBS after configuration change
oc rollout restart deployment/kbs -n trustee-operator-system
```

## Production Considerations

### TLS Certificates

For production deployments:
- Replace self-signed certificates with CA-signed certificates
- Update `kbs-https-certificate` and `kbs-https-key` secrets
- Configure route with edge TLS termination

### Reference Values

- Maintain reference values in a secure, version-controlled location
- Update RVPS when base images or firmware change
- Regularly audit PCR values
- Keep a registry of approved container image digests

### Monitoring

Monitor KBS health and attestation requests:
```bash
# Watch KBS pods
oc get pods -n trustee-operator-system -l app=kbs -w

# Monitor attestation requests
oc logs -n trustee-operator-system deployment/kbs -f | grep attestation

# Check for errors
oc logs -n trustee-operator-system deployment/kbs | grep -i error
```

## Documentation

For detailed documentation, see:
- [06-trustee-attestation.md](../../docs/06-trustee-attestation.md) - Complete Trustee documentation
- [Red Hat Trustee Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_trustee/0.4.2)

## Troubleshooting

### KBS Pod Not Starting

```bash
# Check secret mounts
oc describe pod -n trustee-operator-system -l app=kbs

# Verify all required secrets exist
oc get secrets -n trustee-operator-system | grep kbs
```

### Attestation Failures

```bash
# View attestation policy
oc get configmap attestation-policy -n trustee-operator-system -o yaml

# Check KBS logs for errors
oc logs -n trustee-operator-system deployment/kbs --tail=100
```

### PCR Mismatch

If attestation fails due to PCR mismatch:
1. Extract current PCR values from the workload
2. Compare with values in RVPS
3. Update RVPS if the mismatch is expected (e.g., after kernel update)

```bash
# Get PCR values from workload
oc exec <pod-name> -n janine-app -- cat /sys/kernel/security/tpm0/ascii_bios_measurements
```

## Integration with Peer Pods

Trustee integrates with OpenShift Sandboxed Containers to provide attestation for confidential peer pods:

1. Peer pod requests attestation token from KBS
2. KBS validates vTPM SNP evidence
3. KBS issues attestation token if validation passes
4. Workload uses attestation token to request secrets/keys

See `docs/06-trustee-attestation.md` for complete workflow details.
