#!/usr/bin/env bash
# Run the S3 client inside the Kind network; never edit RustFS's backing files.
# Usage: lab/object-store.sh eu rm --recursive --force lab/backups/pg-eu
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/common.sh"
region=${1:?region required}; shift
exec "$CONTAINER_PROVIDER" run --rm --network kind \
  -e "MC_HOST_lab=http://${RUSTFS_ROOT_USER}:${RUSTFS_ROOT_PASSWORD}@${RUSTFS_BASE_NAME}-${region}:9000" \
  "$RUSTFS_RC_IMAGE" "$@"
