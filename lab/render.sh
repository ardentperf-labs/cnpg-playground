#!/usr/bin/env bash
# Render upstream's current templates for the lab's EU/US topology.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
export KUBECONFIG="$ROOT/k8s/kube-config.yaml"
OUT="$ROOT/lab/generated"
mkdir -p "$OUT"
DRY_RUN=true OUTPUT_DIR="$OUT" demo/setup.sh eu us
python3 - "$OUT" <<'PY'
import pathlib, sys, yaml
out = pathlib.Path(sys.argv[1])
for region in ('eu', 'us'):
    docs = list(yaml.safe_load_all((out / f'{region}.yaml').read_text()))
    cluster = next(d for d in docs if d and d.get('kind') == 'Cluster')
    (out / f'pg-{region}.yaml').write_text(yaml.safe_dump(cluster, sort_keys=False))
PY
