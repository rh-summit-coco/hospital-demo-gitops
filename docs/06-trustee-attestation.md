# Red Hat build of Trustee - Attestation and Key Management

## Overview

The Red Hat build of Trustee provides attestation and key management services for confidential containers running on Azure. It consists of three main components:

1. **Key Broker Service (KBS)**: Distributes secrets and keys to attested workloads
2. **Attestation Service (AS)**: Validates workload attestation using vTPM SNP on Azure
3. **Reference Value Provider Service (RVPS)**: Stores reference values for attestation validation

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Confidential Workload (Peer Pod on Azure)              │
│  ┌────────────────────────────────────────────┐         │
│  │  1. Request attestation token              │         │
│  │  2. Provide vTPM SNP evidence              │         │
│  └────────────────────────────────────────────┘         │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  Trustee Key Broker Service (KBS)                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Attestation │  │    RVPS      │  │   Resource   │  │
│  │   Service    │─▶│  (Reference  │◀─│   Policy     │  │
│  │   (AS)       │  │   Values)    │  │   Engine     │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│         │                                     │          │
│         ▼                                     ▼          │
│  ┌──────────────────────────────────────────────────┐  │
│  │  3. Validate PCR values                          │  │
│  │  4. Validate container image signature           │  │
│  │  5. Issue attestation token                      │  │
│  │  6. Provide secrets/keys based on policy         │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. Key Broker Service (KBS)

The KBS is the main entry point for workloads requesting secrets. It:
- Receives attestation requests from confidential workloads
- Validates attestation evidence via the Attestation Service
- Enforces resource access policies
- Distributes secrets and keys to validated workloads

**Configuration**: `operators/trustee/kbs-config-cm.yaml`

### 2. Attestation Service (AS)

The AS validates workload attestation using Azure vTPM SNP (Secure Nested Paging):
- Verifies Platform Configuration Registers (PCRs)
- Validates container image signatures
- Issues attestation tokens for approved workloads

**Policy**: `operators/trustee/attestation-policy.yaml`

**Key PCR Values for Azure vTPM SNP**:
- **PCR 03**: Firmware and UEFI boot measurements
- **PCR 08**: Kernel command line
- **PCR 09**: Kernel image and initrd
- **PCR 11**: Boot configuration
- **PCR 12**: Kernel command line and initrd

### 3. Reference Value Provider Service (RVPS)

The RVPS stores reference values used for attestation validation:
- PCR values for trusted boot chains
- Container image digests
- Firmware measurements

**Configuration**: `operators/trustee/rvps-reference-values.yaml`

## Azure-Specific Configuration

### vTPM SNP Support

Azure confidential VMs use vTPM (Virtual Trusted Platform Module) with SNP (Secure Nested Paging) technology. The Trustee attestation policy is configured to:

1. Verify the TEE type is `azsnpvtpm`
2. Validate PCR measurements against reference values
3. Verify container image signatures

### PCR Measurement Flow

1. **Boot**: Azure measures boot components into PCRs 0-7
2. **Kernel**: Kernel and initrd measured into PCR 09
3. **Command Line**: Kernel parameters measured into PCR 08 and 12
4. **Configuration**: Boot configuration measured into PCR 11
5. **UEFI**: Firmware components measured into PCR 03

## Security Policies

### Container Image Verification

The security policy (`operators/trustee/security-policy.yaml`) enforces:
- All images must be signed
- Signatures verified using GPG keys
- Trusted registries:
  - `quay.io`
  - `registry.redhat.io`
  - `registry.access.redhat.com`

### Resource Access Control

The resource policy (`operators/trustee/resource-policy.yaml`) controls:
- Which workloads can access encryption keys
- Configuration access based on attestation
- Certificate distribution for TLS workloads

## Deployment

### Prerequisites

- OpenShift Sandboxed Containers operator installed
- Peer pods configured for Azure
- TLS certificates (self-signed for dev, CA-signed for production)

### Installation Steps

1. **Create Secrets**:
   ```bash
   chmod +x automation/scripts/create-trustee-secrets.sh
   ./automation/scripts/create-trustee-secrets.sh
   ```

2. **Deploy via GitOps**:
   The Trustee operator and configuration are automatically deployed via ArgoCD ApplicationSet.

3. **Verify Installation**:
   ```bash
   # Check operator
   oc get operators.operators.coreos.com trustee-operator.trustee-operator-system

   # Check KbsConfig
   oc get kbsconfig kbsconfig -n trustee-operator-system

   # Check KBS deployment
   oc get deployment kbs -n trustee-operator-system

   # Check KBS service
   oc get service kbs-service -n trustee-operator-system
   ```

### Update Reference Values

After initial deployment, you must populate the RVPS with reference values:

```bash
# Get PCR values from a trusted peer pod
oc exec -it <trusted-pod> -- cat /sys/kernel/security/tpm0/binary_bios_measurements

# Update RVPS ConfigMap with PCR values
oc edit configmap rvps-reference-values -n trustee-operator-system
```

Example RVPS reference values:
```json
[
  {
    "name": "azure-vtpm-snp",
    "pcrs": {
      "03": "<sha256-hash>",
      "08": "<sha256-hash>",
      "09": "<sha256-hash>",
      "11": "<sha256-hash>",
      "12": "<sha256-hash>"
    }
  },
  {
    "name": "container-images",
    "images": [
      {
        "image": "registry.redhat.io/openshift-sandboxed-containers/peer-pod:1.10",
        "digest": "sha256:..."
      }
    ]
  }
]
```

## Testing Attestation

### Create a Confidential Workload

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: confidential-workload
  namespace: janine-app
spec:
  runtimeClassName: kata-remote
  containers:
  - name: app
    image: registry.redhat.io/ubi9/ubi-minimal:latest
    command: ["sleep", "infinity"]
    env:
    - name: KBS_URL
      value: "https://kbs-service.trustee-operator-system.svc:8080"
```

### Request Secret from KBS

Inside the confidential workload:

```bash
# Get attestation token
curl -X POST $KBS_URL/attestation \
  -H "Content-Type: application/json" \
  -d '{"tee":"azsnpvtpm"}' \
  --cacert /etc/kbs/ca.crt

# Request secret
curl -X GET $KBS_URL/resource/my-namespace/my-secret \
  -H "Authorization: Bearer $ATTESTATION_TOKEN" \
  --cacert /etc/kbs/ca.crt
```

## Production Considerations

### TLS Certificates

For production:
1. Obtain CA-signed certificate for KBS service
2. Create route with valid certificate
3. Update `kbs-https-certificate` and `kbs-https-key` secrets

```bash
# Create production certificates
oc create secret tls kbs-https-certificate \
  --cert=kbs-cert.pem \
  --key=kbs-key.pem \
  -n trustee-operator-system
```

### Reference Value Management

- Store reference values in a secure location
- Use CI/CD to update RVPS when base images change
- Regularly audit and update PCR values
- Maintain a registry of trusted container images

### Monitoring and Logging

```bash
# View KBS logs
oc logs -n trustee-operator-system deployment/kbs

# Monitor attestation requests
oc logs -n trustee-operator-system deployment/kbs | grep "attestation request"

# Check failed attestations
oc logs -n trustee-operator-system deployment/kbs | grep "attestation failed"
```

## Troubleshooting

### KBS Pod Not Starting

```bash
# Check secret mounts
oc describe pod -n trustee-operator-system -l app=kbs

# Verify secrets exist
oc get secrets -n trustee-operator-system | grep kbs
```

### Attestation Failures

```bash
# Check attestation policy
oc get configmap attestation-policy -n trustee-operator-system -o yaml

# View detailed KBS logs
oc logs -n trustee-operator-system deployment/kbs --tail=100
```

### PCR Mismatch

If attestation fails due to PCR mismatch:
1. Extract PCR values from the failing workload
2. Verify they match expected values
3. Update RVPS reference values if the mismatch is expected (e.g., kernel update)

```bash
# Get current PCR values from workload
oc exec <pod-name> -n janine-app -- cat /sys/kernel/security/tpm0/ascii_bios_measurements
```

## References

- [Red Hat build of Trustee Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_trustee/0.4.2)
- [Azure Confidential Computing](https://docs.microsoft.com/azure/confidential-computing/)
- [vTPM Attestation](https://docs.microsoft.com/azure/confidential-computing/virtual-machine-solutions)
- [OPA Policy Language](https://www.openpolicyagent.org/docs/latest/policy-language/)

## Security Best Practices

1. **Rotate Certificates Regularly**: Update TLS certificates before expiration
2. **Audit Reference Values**: Review and update reference values regularly
3. **Monitor Attestation Logs**: Track attestation requests and failures
4. **Restrict KBS Access**: Use network policies to limit KBS access
5. **Secure Key Material**: Store KBS authentication keys in a secure vault
6. **Validate Container Images**: Only allow signed images from trusted registries
7. **Update Policies**: Keep attestation and resource policies up to date
8. **Test Attestation**: Regularly test attestation flows in non-production environments

---

**Next Steps**:
- Configure reference values for your workloads
- Set up CA-signed certificates for production
- Integrate with your secret management workflow
- Test attestation with sample confidential workloads
