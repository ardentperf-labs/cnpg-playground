#!/usr/bin/env bash
# Local Ubuntu Server VM using KVM. Requires qemu-system-x86, qemu-utils,
# cloud-image-utils, curl, python3 and openssh-client on the Linux host.
set -euo pipefail
VM_DIR=${VM_DIR:-"$HOME/.local/share/cnpg-lab-vm"}
mkdir -p "$VM_DIR"
chmod 700 "$VM_DIR"
cd "$VM_DIR"
if [[ -e lab.qcow2 ]]; then
    echo "VM disk already exists in $VM_DIR; use start.sh to resume it." >&2
    exit 1
fi
for cmd in qemu-system-x86_64 qemu-img cloud-localds curl python3 ssh-keygen; do
    command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done
sudo -n test -c /dev/kvm
base=https://cloud-images.ubuntu.com/releases/26.04/release
curl -fL --retry 3 "$base/ubuntu-26.04-server-cloudimg-amd64.img" -o ubuntu-26.04.img
curl -fsSL "$base/SHA256SUMS" -o SHA256SUMS
python3 - <<'PY'
import hashlib, pathlib
expected = next(line.split()[0] for line in pathlib.Path('SHA256SUMS').read_text().splitlines()
                if line.endswith('ubuntu-26.04-server-cloudimg-amd64.img'))
with open('ubuntu-26.04.img', 'rb') as image:
    assert hashlib.file_digest(image, 'sha256').hexdigest() == expected, 'Image checksum mismatch'
PY
ssh-keygen -q -t ed25519 -N '' -f id_ed25519
umask 077
python3 - <<'PY'
import json, pathlib, secrets
password = secrets.token_urlsafe(24)
pathlib.Path('rdp-password').write_text(password + '\n')
config = {'hostname': 'cnpg-lab', 'users': [{'name': 'ubuntu', 'groups': ['sudo'],
          'sudo': 'ALL=(ALL) NOPASSWD:ALL', 'shell': '/bin/bash', 'lock_passwd': False,
          'ssh_authorized_keys': [pathlib.Path('id_ed25519.pub').read_text().strip()]}],
          'chpasswd': {'expire': False, 'users': [{'name': 'ubuntu', 'password': password, 'type': 'text'}]},
          'write_files': [{'path': '/home/ubuntu/.cnpg-rdp-password', 'owner': 'ubuntu:ubuntu',
                           'permissions': '0600', 'defer': True, 'content': password + '\n'}],
          'ssh_pwauth': False}
pathlib.Path('user-data').write_text('#cloud-config\n' + json.dumps(config))
pathlib.Path('meta-data').write_text('instance-id: cnpg-lab-2604\nlocal-hostname: cnpg-lab\n')
PY
cloud-localds seed.img user-data meta-data
qemu-img create -f qcow2 -F qcow2 -b "$VM_DIR/ubuntu-26.04.img" lab.qcow2 100G
cat > start.sh <<'START'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sudo qemu-system-x86_64 -name cnpg-lab-2604 -enable-kvm -cpu host -smp 4 -m 16384 \
    -drive file="$PWD/lab.qcow2",format=qcow2,if=virtio \
    -drive file="$PWD/seed.img",format=raw,if=virtio \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:13389-:3389 \
    -display none -serial file:"$PWD/serial.log" -daemonize -pidfile "$PWD/qemu.pid"
START
chmod +x start.sh
./start.sh
cat <<INFO
VM started: 4 vCPUs, 16 GiB RAM, 100 GiB disk.
SSH (after cloud-init finishes):
  ssh -i '$VM_DIR/id_ed25519' -p 2222 ubuntu@127.0.0.1
RDP after lab installation: 127.0.0.1:13389, user ubuntu.
The generated password is in $VM_DIR/rdp-password (mode 600).
Shut down using 'sudo poweroff' inside the guest; resume using $VM_DIR/start.sh.
INFO
