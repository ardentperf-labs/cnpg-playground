#!/usr/bin/env bash
# Read-only baseline checks after exercises 1 and 2 and monitoring/setup.sh.
# Run inside the Ubuntu guest.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export KUBECONFIG="$ROOT/k8s/kube-config.yaml"
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 26.04 ]]
systemctl is-active docker xrdp
printf 'Ubuntu %s; %s CPUs; %s\n' "$VERSION_ID" "$(nproc)" "$(free -h | awk '/Mem:/ {print $2 " RAM"}')"
for region in eu us; do
    context=kind-k8s-$region
    kubectl --context "$context" wait node --all --for=condition=Ready --timeout=120s
    kubectl --context "$context" wait cluster/pg-$region --for=condition=Ready --timeout=300s
    kubectl --context "$context" get cluster/pg-$region
    expected=f; [[ "$region" == us ]] && expected=t
    primary=$(kubectl --context "$context" get cluster/pg-$region -o jsonpath='{.status.currentPrimary}')
    actual=$(kubectl --context "$context" exec "$primary" -c postgres -- \
        psql -U postgres -Atc 'SELECT pg_is_in_recovery()')
    [[ "$actual" == "$expected" ]]
    kubectl --context "$context" get pods -A
    echo "PASS: $region API, nodes, PostgreSQL and recovery role"
done
