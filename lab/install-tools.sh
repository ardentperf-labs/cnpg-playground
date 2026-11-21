#!/usr/bin/env bash
# Install official release binaries, verifying each publisher's SHA-256 file.
# Ubuntu packages (curl, tar, coreutils) must already be installed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/tool-versions.env"
case "$(uname -m)" in
  x86_64) arch=amd64; goarch=x86_64 ;;
  aarch64|arm64) arch=arm64; goarch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
DEST=${DEST:-/usr/local/bin}
mkdir -p "$DEST"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
fetch() { curl --fail --silent --show-error --location --retry 3 "$1" -o "$2"; }
verify() {
  local file=$1 sums=$2
  awk -v f="$file" '$2 == f || $2 == "*" f {print}' "$sums" > selected.sha256
  [[ -s selected.sha256 ]] || { echo "No checksum for $file" >&2; exit 1; }
  sha256sum --check selected.sha256
}
# GitHub release asset, checksum list, and binary path inside tar.gz (or raw).
github_tool() {
  local repo=$1 version=$2 asset=$3 sums=$4 binary=$5 output=$6
  local base="https://github.com/$repo/releases/download/$version"
  fetch "$base/$asset" "$asset"
  fetch "$base/$sums" "$output-checksums"
  verify "$asset" "$output-checksums"
  if [[ "$asset" == *.tar.gz ]]; then
    mkdir -p "$output-extract"
    tar -xzf "$asset" -C "$output-extract" "$binary"
    install -m 0755 "$output-extract/$binary" "$DEST/$output"
  else
    install -m 0755 "$asset" "$DEST/$output"
  fi
}
fetch "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$arch/kubectl" kubectl
fetch "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$arch/kubectl.sha256" kubectl.sha256
printf '%s  kubectl\n' "$(cat kubectl.sha256)" | sha256sum --check
install -m 0755 kubectl "$DEST/kubectl"
github_tool kubernetes-sigs/kind "$KIND_VERSION" "kind-linux-$arch" "kind-linux-$arch.sha256sum" '' kind
github_tool cloudnative-pg/cloudnative-pg "v$CNPG_PLUGIN_VERSION" \
  "kubectl-cnpg_${CNPG_PLUGIN_VERSION}_linux_${goarch}.tar.gz" "cnpg-${CNPG_PLUGIN_VERSION}-checksums.txt" kubectl-cnpg kubectl-cnpg
github_tool cert-manager/cmctl "$CMCTL_VERSION" "cmctl_linux_$arch" checksums.txt '' cmctl
github_tool derailed/k9s "$K9S_VERSION" "k9s_Linux_$arch.tar.gz" checksums.sha256 k9s k9s
github_tool jesseduffield/lazydocker "v$LAZYDOCKER_VERSION" \
  "lazydocker_${LAZYDOCKER_VERSION}_Linux_$goarch.tar.gz" checksums.txt lazydocker lazydocker
github_tool stern/stern "v$STERN_VERSION" "stern_${STERN_VERSION}_linux_$arch.tar.gz" checksums.txt stern stern
asset="helm-$HELM_VERSION-linux-$arch.tar.gz"
fetch "https://get.helm.sh/$asset" "$asset"
fetch "https://get.helm.sh/$asset.sha256sum" helm-checksums
verify "$asset" helm-checksums
tar -xzf "$asset" "linux-$arch/helm"
install -m 0755 "linux-$arch/helm" "$DEST/helm"
echo "Installed lab tools to $DEST"
