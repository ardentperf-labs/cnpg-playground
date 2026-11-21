#!/usr/bin/env bash
# Kept as a compatibility entry point; the playground now uses RustFS.
echo "The playground now uses RustFS. Inspect cluster logs for archive errors." >&2
echo "After deleting a test cluster, use lab/object-store.sh REGION rm --recursive --force lab/backups/pg-REGION to clear its archive." >&2
exit 1
