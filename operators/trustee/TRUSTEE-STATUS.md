# Trustee Operator Status

## Current Deployment Status: ⚠️ BLOCKED

### Version Information
- **Red Hat Trustee Operator**: v0.4.2
- **Namespace**: trustee-operator-system
- **KBS Deployment**: `trustee-deployment`

### Known Issues with Red Hat v0.4.2

#### 1. Admin Configuration Incompatibility ❌ BLOCKING
**Status**: Cannot start KBS with any admin backend configuration

**Error**:
```
Error: Admin auth error: `auth_public_key` is not set in the config file
```

**Tested Configurations**:
- ❌ `InsecureAllowAll` - Still requires auth_public_key
- ❌ `DenyAll` - Still requires auth_public_key
- ❌ `Simple` - Requires auth_public_key (expected)

**Root Cause**: Red Hat's v0.4.2 build has incompatible admin configuration handling compared to upstream. Even with `auth_public_key` present in config and file mounted at `/etc/auth-secret/key.pem`, KBS fails to recognize it.

**Workarounds Attempted**:
- Added/removed `auth_public_key` from top-level config
- Tried all three admin backend types
- Verified auth-secret volume mount and file presence

**Resolution**: Requires upstream fix from Red Hat Trustee operator team OR upgrade to v0.5.0+ when available

#### 2. Missing attestation-policy-dir Volume ⚠️ MITIGATED
**Status**: Fixed in upstream v0.5.0 (commit d7b6419, Aug 13, 2025)

**Impact**: Operator doesn't create `attestation-policy-dir` emptyDir volume, would cause permission errors if AS tries to write policies.

**Mitigation**: Not currently hitting this issue, but will be a problem for policy management.

#### 3. Missing fsGroup Security Context ⚠️ MITIGATED
**Status**: Ongoing limitation in v0.4.2

**Impact**: emptyDir volumes owned by root, OpenShift assigns random UID without fsGroup, limiting write access.

**Mitigation**: Use world-writable directories like `/opt/confidential-containers/kbs/repository/default/`

### Current Configuration

**KBS Config** (`kbs-config-cm.yaml`):
```toml
insecure_http = false
sockets = ["0.0.0.0:8080"]
auth_public_key = "/etc/auth-secret/key.pem"

[admin]
type = "DenyAll"

[attestation_token_config]
attestation_token_type = "CoCo"

[repository_config]
type = "LocalFs"
dir_path = "/opt/confidential-containers/kbs/repository"

[attestation_service]
type = "CoCoASBuiltIn"

[attestation_service.as_config]
work_dir = "/opt/confidential-containers/attestation-service"
attestation_token_broker = "Simple"

[attestation_service.as_config.attestation_token_config]
duration_min = 5

[attestation_service.as_config.rvps_config]
store_type = "LocalJson"

[attestation_service.as_config.rvps_config.store_config]
file_path = "/opt/confidential-containers/rvps/reference-values/reference-values.json"

[policy_engine]
policy_path = "/opt/confidential-containers/kbs/repository/default/policy.rego"
```

### RVPS Architecture

**Deployment Mode**: Built-in (integrated with KBS)
- When using `CoCoASBuiltIn` attestation service, RVPS runs embedded within the KBS process
- No separate RVPS service/binary in Red Hat trustee image
- Reference values stored at: `/opt/confidential-containers/rvps/reference-values/reference-values.json`

**How RVPS Works**:
1. Receives software supply chain provenance/metadata via API
2. Verifies and extracts reference values
3. Stores values in LocalJson backend
4. Attestation Service queries RVPS for reference values during attestation

**RVPS Client Tool**:
- `rvps-tool` can register and query reference values
- Requires gRPC connection to running RVPS/KBS service
- Not currently functional due to KBS startup failures

### Demo Impact

**What's Blocked**:
- ❌ KBS/RVPS service not running
- ❌ Cannot register reference values from build pipelines
- ❌ Cannot test secret distribution to attested workloads
- ❌ Cannot demonstrate two-gate Zero Trust model

**What Can Proceed**:
- ✅ Build Tekton pipeline structure (mock RVPS API calls)
- ✅ Build hospital AI application (mock secret retrieval)
- ✅ Build Raj's monitoring dashboard (show mock attestation data)
- ✅ Create reference architecture documentation
- ✅ Prepare demo narrative and personas

### Next Steps

**For Summit Demo**:
1. Build demo components with mock RVPS/KBS integration
2. Document expected behavior with working RVPS
3. Create architecture diagrams showing intended flow
4. Prepare fallback demo scenario without live attestation

**For Production Readiness**:
1. Escalate admin configuration issue to Red Hat Trustee team
2. Request early access to operator v0.5.0+
3. Test upstream Trustee directly (outside operator) as alternative
4. Consider contributing fix back to Red Hat operator

### References

- [Trustee GitHub](https://github.com/confidential-containers/trustee)
- [RVPS Documentation](/tmp/trustee/rvps/README.md)
- [KBS Policy Engine Source](/tmp/trustee/kbs/src/policy_engine/)
- [Red Hat Trustee Operator v0.4.2](https://catalog.redhat.com/software/containers/)

---
**Last Updated**: 2025-11-09
**Status Confirmed**: DenyAll admin backend tested, same auth_public_key error persists
