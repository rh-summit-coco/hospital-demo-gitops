#!/bin/bash
# Create required secrets for Red Hat build of Trustee operator
# Based on Red Hat Trustee 0.4.2 documentation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="trustee-operator-system"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Red Hat Trustee - Secrets Creation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"

# Check if namespace exists
if ! oc get namespace ${NAMESPACE} &>/dev/null; then
    echo -e "${YELLOW}Creating namespace ${NAMESPACE}...${NC}"
    oc create namespace ${NAMESPACE}
fi

# 1. Create HTTPS certificate and key
echo -e "${YELLOW}Creating HTTPS certificate and key for KBS...${NC}"
TEMP_DIR=$(mktemp -d)
cd ${TEMP_DIR}

# Generate self-signed certificate for development
# In production, use CA-signed certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout kbs-key.pem \
  -out kbs-cert.pem \
  -subj "/CN=kbs-service.trustee-operator-system.svc/O=Red Hat/C=US"

# Create HTTPS certificate secret
oc create secret generic kbs-https-certificate \
  -n ${NAMESPACE} \
  --from-file=tls.crt=kbs-cert.pem \
  --dry-run=client -o yaml | oc apply -f -

# Create HTTPS key secret
oc create secret generic kbs-https-key \
  -n ${NAMESPACE} \
  --from-file=tls.key=kbs-key.pem \
  --dry-run=client -o yaml | oc apply -f -

echo -e "${GREEN}✓ HTTPS certificate and key secrets created${NC}"

# 2. Create attestation token secret
echo -e "${YELLOW}Creating attestation token secret...${NC}"

# Generate a secure token for attestation
ATTESTATION_TOKEN=$(openssl rand -base64 32)

oc create secret generic kbs-attestation-token \
  -n ${NAMESPACE} \
  --from-literal=token=${ATTESTATION_TOKEN} \
  --dry-run=client -o yaml | oc apply -f -

echo -e "${GREEN}✓ Attestation token secret created${NC}"

# 3. Create authentication secret (public key for JWT validation)
echo -e "${YELLOW}Creating authentication secret...${NC}"

# Generate RSA key pair for JWT authentication
ssh-keygen -t rsa -b 2048 -f kbs-auth-key -N "" -m PEM

# Extract public key in PEM format
ssh-keygen -f kbs-auth-key.pub -e -m PEM > kbs-auth-public.pem

oc create secret generic kbs-auth-public-key \
  -n ${NAMESPACE} \
  --from-file=key.pem=kbs-auth-public.pem \
  --dry-run=client -o yaml | oc apply -f -

echo -e "${GREEN}✓ Authentication secret created${NC}"

# Cleanup
cd -
rm -rf ${TEMP_DIR}

echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Secrets Created Successfully${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "Created secrets in namespace: ${NAMESPACE}"
echo -e "  - kbs-https-certificate"
echo -e "  - kbs-https-key"
echo -e "  - kbs-attestation-token"
echo -e "  - kbs-auth-public-key"
echo -e "\n${YELLOW}NOTE: Self-signed certificates are used for development.${NC}"
echo -e "${YELLOW}For production, replace with CA-signed certificates.${NC}"
