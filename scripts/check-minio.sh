#!/usr/bin/env bash
#
# Check for barman WAL archive errors caused by pre-existing files in RustFS.
#
# Usage:
#   ./scripts/check-minio.sh             # Check all regions
#   ./scripts/check-minio.sh eu          # Check specific region
#   ./scripts/check-minio.sh --cleanup   # Cleanup regions with errors
#

source "$(dirname "$0")/common.sh"

# Parse --cleanup flag
DO_CLEANUP=false
ARGS=()
for arg in "$@"; do
    [[ "$arg" == "--cleanup" || "$arg" == "-c" ]] && DO_CLEANUP=true || ARGS+=("$arg")
done

detect_running_regions "${ARGS[@]}"
[[ ${#REGIONS[@]} -eq 0 ]] && echo "❌ No regions found. Is the playground running?" && exit 1

errors_found=()

for region in "${REGIONS[@]}"; do
    context=$(get_cluster_context "${region}")
    cluster_name="pg-${region}"

    echo "📍 Checking region: ${region}"

    # Capture any "Expected empty archive" errors from recent logs
    errors=$(kubectl logs -l cnpg.io/cluster="${cluster_name}" \
        --context "${context}" --since=5m 2>/dev/null | grep "Expected empty archive" || true)

    if [[ -n "$errors" ]]; then
        echo "$errors"
        errors_found+=("${region}")

        if [[ "$DO_CLEANUP" == true ]]; then
            "${REPO_ROOT}/lab/object-store.sh" "$region" rm --recursive --force "lab/backups/${cluster_name}/"
            echo "   ✅ Cleaned ${RUSTFS_BASE_NAME}-${region}/backups/${cluster_name}"
        fi
    else
        echo "   ✅ No errors"
    fi
    echo
done

if [[ ${#errors_found[@]} -gt 0 && "$DO_CLEANUP" == false ]]; then
    echo "To cleanup, run:  ./scripts/check-minio.sh --cleanup ${errors_found[*]}"
fi
