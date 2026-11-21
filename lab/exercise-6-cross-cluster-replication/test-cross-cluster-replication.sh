#!/bin/bash
#
# Test script for Exercise 6: Cross-Cluster Replication with mTLS
# This script sets up pg-us in the kind-k8s-us cluster to replicate from
# pg-eu in kind-k8s-eu, using certificates from the same root CA.
#
# Prerequisites: Exercise 5 must be completed first

set -e

echo "=========================================="
echo "Exercise 6: Cross-Cluster Replication Test"
echo "=========================================="
echo ""

# Save current context
EU_CONTEXT="kind-k8s-eu"
US_CONTEXT="kind-k8s-us"
ORIGINAL_CONTEXT=$(kubectl config current-context)

# Check if both contexts exist
echo "Checking Kubernetes contexts..."
if ! kubectl config get-contexts $EU_CONTEXT &>/dev/null; then
    echo "ERROR: Context $EU_CONTEXT not found."
    echo "Please run the playground setup script first."
    exit 1
fi
if ! kubectl config get-contexts $US_CONTEXT &>/dev/null; then
    echo "ERROR: Context $US_CONTEXT not found."
    echo "Please run the playground setup script first."
    exit 1
fi
echo "✓ Both EU and US clusters available"
echo ""

# Clean up any existing pg-us cluster from initial setup
echo "Cleaning up any existing pg-us cluster from previous setup..."
kubectl config use-context $US_CONTEXT > /dev/null

if kubectl get cluster pg-us &>/dev/null; then
    echo "  Found existing pg-us cluster, removing it..."
    kubectl delete cluster pg-us --wait=false
    
    # Wait for deletion
    echo "  Waiting for pg-us to be deleted..."
    kubectl wait --for=delete cluster/pg-us --timeout=60s 2>/dev/null || true
    
    # Clean up any leftover resources
    kubectl delete pods -l cnpg.io/cluster=pg-us --ignore-not-found=true 2>/dev/null || true
    kubectl delete pvc -l cnpg.io/cluster=pg-us --ignore-not-found=true 2>/dev/null || true
    
    echo "  ✓ Existing pg-us cluster removed"
else
    echo "  No existing pg-us cluster found"
fi

# Clean up RustFS US backup data
echo "  Cleaning RustFS-US backup data..."
lab/object-store.sh us rm --recursive --force lab/backups/pg-us 2>/dev/null || true
echo "  ✓ RustFS-US cleaned"
echo ""

# Switch to EU context to check prerequisites
kubectl config use-context $EU_CONTEXT > /dev/null
echo "Checking prerequisites in EU cluster..."
if ! kubectl get certificate pg-eu-root-ca &>/dev/null; then
    echo "ERROR: pg-eu certificates not found in $EU_CONTEXT."
    echo "Please complete Exercise 5 first:"
    echo "  bash lab/exercise-5-pgbouncer-mtls/test-pgbouncer-mtls-setup.sh"
    exit 1
fi
echo "✓ pg-eu certificates found in EU cluster"

if ! kubectl get cluster pg-eu &>/dev/null; then
    echo "ERROR: pg-eu cluster not found in $EU_CONTEXT."
    exit 1
fi
echo "✓ pg-eu cluster running in EU cluster"
echo ""

# Copy only Root CA to US cluster
echo "Step 1: Copying Root CA from EU to US cluster..."
kubectl config use-context $US_CONTEXT > /dev/null

# Export and import only the Root CA secret from EU to US
echo "Copying Root CA (pg-eu-root-ca)..."
kubectl --context=$EU_CONTEXT get secret pg-eu-root-ca -o json | \
    jq '{apiVersion,kind,metadata:{name:.metadata.name},type,data}' | \
    kubectl --context=$US_CONTEXT apply -f -
echo "✓ Root CA copied to US cluster"
echo ""

# Create intermediate CAs and certificates in US cluster
echo "Step 2: Creating intermediate CAs and certificates in US cluster..."
kubectl apply -f lab/exercise-6-cross-cluster-replication/pg-us-certs.yaml
echo ""

# Wait for intermediate CAs first
echo "Waiting for intermediate CAs to be ready..."
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-us-server-ca certificate/pg-us-client-ca
echo "✓ Intermediate CAs ready"
echo ""

# Wait for certificates
echo "Waiting for pg-us certificates to be ready..."
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-us-server-cert
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-us-replication-cert
kubectl wait --timeout=2m --for=condition=Ready certificate/pg-us-app-cert
echo "✓ pg-us certificates ready"
echo ""

# Merge this exercise into the locally rendered upstream manifest.
test -f lab/generated/pg-eu.yaml || { echo "Run lab/render.sh first" >&2; exit 1; }
python3 lab/patch-cluster.py lab/generated/pg-us.yaml lab/exercise-6-cross-cluster-replication/pg-us.yaml
kubectl --context kind-k8s-us apply -f lab/generated/pg-us.yaml

# Wait for pg-us to be ready
echo "Waiting for pg-us cluster to be ready (this may take several minutes)..."
kubectl wait --timeout=10m --for=condition=Ready cluster/pg-us
# Wait for running pods (not completed init pods)
kubectl wait --timeout=5m --for=condition=Ready pod -l cnpg.io/cluster=pg-us,cnpg.io/podRole=instance
echo "✓ pg-us cluster ready in US cluster"
echo ""

# Verify bootstrap data exists on pg-us
echo "Step 5: Verifying pg-us bootstrapped from pg-eu backup..."
kubectl config use-context $US_CONTEXT > /dev/null

echo "Checking if data from pg-eu exists on pg-us..."
# Exercise 5 loads pgbench in the app database. Read it on the standby.
verified=$(kubectl exec pg-us-1 -c postgres -- psql -XAt -v ON_ERROR_STOP=1 -d app \
    -c 'SELECT pg_is_in_recovery() AND EXISTS (SELECT FROM pgbench_accounts LIMIT 1)')
if [[ "$verified" != t ]]; then
    echo "Expected a standby with replicated pgbench data" >&2
    exit 1
fi
echo "✓ The US standby contains the application benchmark data"

kubectl exec pg-us-1 -c postgres -- psql -d app -c \
    'SELECT pg_is_in_recovery() AS is_replica, pg_last_wal_replay_lsn() AS last_replay_lsn'
echo ""

# Verify certificates are being used
echo "Step 7: Verifying mTLS certificates..."
kubectl config use-context $US_CONTEXT > /dev/null
echo "Checking pg-us certificates:"
kubectl get certificate -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,ISSUER:.spec.issuerRef.name
echo ""

# Test cross-cluster mTLS: US client -> EU PgBouncer
echo "Step 8: Testing cross-cluster mTLS connection..."
echo "Testing: US cluster client -> EU cluster PgBouncer (like replication does)"
echo ""

# Reach the EU nodes through Kind's shared Docker network.
kubectl --context kind-k8s-eu expose deployment pg-eu-pooler-rw \
  --name=pg-eu-pooler-test --type=NodePort --port=5432 --target-port=5432 \
  --dry-run=client -o yaml | kubectl --context kind-k8s-eu apply -f -
PGBOUNCER_PORT=$(kubectl --context kind-k8s-eu get svc pg-eu-pooler-test -o jsonpath='{.spec.ports[0].nodePort}')
PGBOUNCER_ADDR=$(kubectl --context kind-k8s-eu get node k8s-eu-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
kubectl config use-context kind-k8s-us

# Deploy test client in US cluster with pg-us client certificates
echo "  Deploying test client in US cluster..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: us-client-to-eu-pgbouncer
spec:
  restartPolicy: Never
  securityContext:
    fsGroup: 26
    runAsUser: 26
    runAsGroup: 26
  containers:
  - name: postgres-client
    image: ghcr.io/cloudnative-pg/postgresql:18
    command: ["/bin/bash", "-c", "sleep 3600"]
    volumeMounts:
    - name: client-cert
      mountPath: /etc/secrets/client
      readOnly: true
    - name: server-ca
      mountPath: /etc/secrets/ca
      readOnly: true
    env:
    - name: PGHOSTADDR
      value: "$PGBOUNCER_ADDR"
    - name: PGCONNECT_TIMEOUT
      value: "10"
    - name: PGSSLCERT
      value: /etc/secrets/client/tls.crt
    - name: PGSSLKEY
      value: /etc/secrets/client/tls.key
    - name: PGSSLROOTCERT
      value: /etc/secrets/ca/ca.crt
    - name: PGSSLMODE
      value: verify-full
  volumes:
  - name: client-cert
    secret:
      secretName: pg-us-app-cert
      defaultMode: 0440
  - name: server-ca
    secret:
      secretName: pg-eu-root-ca
      items:
      - {key: tls.crt, path: ca.crt}
      defaultMode: 0440
EOF

kubectl wait --timeout=60s --for=condition=Ready pod/us-client-to-eu-pgbouncer 2>/dev/null || true
echo ""

# Test connection using the cross-cluster service endpoint
echo "  Testing mTLS connection from US to EU via service endpoint..."
echo "  Target: pg-eu-pooler-test at $PGBOUNCER_ADDR:$PGBOUNCER_PORT"
echo ""

if ! CONNECT_RESULT=$(kubectl exec us-client-to-eu-pgbouncer -- psql \
    -h pg-eu-pooler-rw.default.svc.cluster.local \
    -p "$PGBOUNCER_PORT" \
    -U app \
    -d app \
    -c "SELECT 'Cross-cluster mTLS SUCCESS!' AS result, current_database() AS database, inet_server_addr() AS server;" \
    2>&1); then
    echo "$CONNECT_RESULT" >&2
    exit 1
fi

if echo "$CONNECT_RESULT" | grep -q "Cross-cluster mTLS SUCCESS"; then
    echo "✓ Cross-cluster mTLS connection successful!"
    echo ""
    echo "$CONNECT_RESULT" | grep -A3 "result"
    echo ""
    echo "This proves:"
    echo "  • US client cert (signed by pg-us-client-ca) is trusted by EU PgBouncer"
    echo "  • Certificate chain validates: US cert → US intermediate CA → Shared Root CA"
    echo "  • Unified PKI enables seamless cross-cluster authentication"
else
    echo "⚠ Cross-cluster connection failed or unexpected result:"
    echo "$CONNECT_RESULT" >&2
    exit 1
fi
echo ""

# Verify certificate details
echo "  Client certificate details:"
kubectl exec us-client-to-eu-pgbouncer -- openssl x509 -in /etc/secrets/client/tls.crt -noout -subject -issuer 2>/dev/null
echo ""

# Cleanup
kubectl delete pod us-client-to-eu-pgbouncer --ignore-not-found=true 2>/dev/null
kubectl --context kind-k8s-eu delete service pg-eu-pooler-test --ignore-not-found=true
echo "  ℹ Cleaned up test resources"
echo ""

# Restore original context
kubectl config use-context $ORIGINAL_CONTEXT > /dev/null

echo "=========================================="
echo "Exercise 6: Cross-Cluster Replication COMPLETE!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Root CA copied from EU cluster (kind-k8s-eu) to US cluster (kind-k8s-us)"
echo "  ✓ US intermediate CAs created from shared Root CA"
echo "  ✓ pg-us certificates created in US cluster"
echo "  ✓ pg-us cluster deployed and bootstrapped from pg-eu backup"
echo "  ✓ Cross-cluster mTLS connection verified (US client -> EU PgBouncer)"
echo "  ✓ Unified PKI across clusters demonstrated"
echo ""
echo "Architecture:"
echo "  EU Cluster (kind-k8s-eu): pg-eu (primary, read-write) with PgBouncer"
echo "  US Cluster (kind-k8s-us): pg-us (standby, read-only, bootstrapped from EU backup)"
echo "  Certificate Authority: Shared Root CA, region-specific Intermediate CAs"
echo "  Cross-Cluster Access: US clients can authenticate to EU PgBouncer using mTLS"
echo ""
echo "Next steps:"
echo "  - Query from US cluster: kubectl --context=kind-k8s-us exec -it pg-us-1 -- psql -U postgres"
echo "  - Monitor replication lag"
echo "  - Test failover scenarios"
echo ""
echo "Cleanup:"
echo "  bash lab/exercise-6-cross-cluster-replication/cleanup.sh"
echo ""
