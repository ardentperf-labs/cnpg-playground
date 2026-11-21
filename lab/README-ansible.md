# Ansible Playbook for Ubuntu 26.04 Desktop Setup

- [Prerequisites](#prerequisites)
- [Usage](#usage)
  - [Basic Usage](#basic-usage)
  - [With Proxy Configuration](#with-proxy-configuration)
- [Classroom Lab Setup](#classroom-lab-setup)
- [What the Ansible Playbook Does](#what-the-ansible-playbook-does)
- [Variables](#variables)
- [Files Created](#files-created)
- [Notes](#notes)

---

This Ansible playbook (`install-core.yml`) contains the core installation logic for setting up a desktop environment on Ubuntu 26.04 Server. It is designed to be called by the `install.sh` shell script wrapper, which handles prechecks and user interaction.

## Prerequisites

- Ubuntu 26.04 Server (not desktop) clean/fresh install on targets
- SSH access to the targets
- Sudo privileges on the targets
- Ansible installed on the targets

## Usage

### Basic Usage

```bash
# Run the playbook against localhost (if running on the target server)
ansible-playbook install-core.yml

# Run against a remote server
ansible-playbook install-core.yml -i inventory.ini
```

### With Proxy Configuration

If you need to configure a proxy for internet access, you can set the variables:

```bash
# Set proxy variables
ansible-playbook install-core.yml -e "use_proxy=true" -e "proxy_ip=192.168.1.1" -e "proxy_port=9000"

# Or use a vars file
ansible-playbook install-core.yml -e "@proxy-vars.yml"
```

Example `proxy-vars.yml`:
```yaml
use_proxy: true
proxy_ip: "192.168.1.1"
proxy_port: 9000
```

## Classroom Lab Setup

For training environments with multiple identical VMs, create a simple inventory file:

```ini
# inventory.ini - 10 identical student VMs
[students]
student01 ansible_host=192.168.1.101 ansible_user=ubuntu
student02 ansible_host=192.168.1.102 ansible_user=ubuntu
student03 ansible_host=192.168.1.103 ansible_user=ubuntu
student04 ansible_host=192.168.1.104 ansible_user=ubuntu
student05 ansible_host=192.168.1.105 ansible_user=ubuntu
student06 ansible_host=192.168.1.106 ansible_user=ubuntu
student07 ansible_host=192.168.1.107 ansible_user=ubuntu
student08 ansible_host=192.168.1.108 ansible_user=ubuntu
student09 ansible_host=192.168.1.109 ansible_user=ubuntu
student10 ansible_host=192.168.1.110 ansible_user=ubuntu

[students:vars]
use_proxy=true
proxy_ip=192.168.1.1
proxy_port=9000
set_user_password=true
user_password=Training2025!
```

Deploy to all VMs:

```bash
# Deploy to all 10 VMs in parallel
ansible-playbook install-core.yml -i inventory.ini -f 10

# Test connectivity first
ansible students -i inventory.ini -m ping
```

**Note**: After running the playbook, remember to reboot all VMs for the desktop environment and system changes to take full effect.

## What the Ansible Playbook Does

1. **Package Installation**:
   - Updates and upgrades packages
   - Installs all required packages in a single operation:
     - ubuntu-desktop-minimal (desktop environment)
     - gnome-remote-desktop (Remote Login)
     - docker.io (container runtime)
     - curl, jq, kubectx, btop, bat, Python/PyYAML and gettext
   - Creates flag file `/etc/desktop-installed-by-cnpg-lab` after successful installation
3. **Docker Configuration**:
   - Adds user to docker group
   - Configures proxy settings if needed
4. **Command-line Tools**:
   - Downloads official binaries to `/usr/local/bin` and verifies SHA-256 checksums
   - Versions are pinned in `tool-versions.env`; rerun `install-tools.sh` to update
5. **System Tuning**:
   - Increases file watch limits for kind clusters
6. **Firefox Setup**:
   - Creates desktop shortcuts
   - Configures homepage and startup behavior
   - Sets up bookmarks toolbar visibility
   - Automatically installs default bookmarks using Firefox Enterprise Policies
7. **Desktop Configuration**:
   - Creates autostart script for GNOME Terminal colors
8. **Development Environment**:
   - Configures KUBECONFIG
   - Sets up aliases and shell completion

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `use_proxy` | `false` | Whether to configure proxy settings |
| `proxy_ip` | Gateway IP | Proxy server IP address |
| `proxy_port` | `9000` | Proxy server port |
| `target_user` | `{{ ansible_user }}` | User to configure |
| `target_user_home` | `/home/{{ target_user }}` | User's home directory |
| `set_user_password` | `false` | Whether to set user password |
| `user_password` | `''` | Password to set for user |
| `script_dir` | `{{ playbook_dir }}/..` | Project directory |
| `homepage_url` | GitHub lab URL | Firefox homepage URL |

## Files Created

- `/etc/desktop-installed-by-cnpg-lab` (flag file indicating the lab desktop was installed by this playbook)
- `/etc/systemd/system/docker.service.d/http-proxy.conf` (if proxy enabled)
- `/etc/sysctl.d/99-inotify.conf` (file watch limits)
- `~/.local/share/applications/firefox.desktop` (Firefox shortcut)
- `~/.config/autostart/firefox.desktop` (Firefox autostart)
- `/etc/firefox/policies/policies.json` (Firefox Enterprise Policies)
- `~/configure-desktop.sh` (Desktop configuration script)
- `~/.config/autostart/configure-desktop.desktop` (Autostart entry)
- Firefox profile with custom homepage and bookmarks toolbar

## Notes

- A reboot is recommended for all changes to take full effect
- The user will be added to docker group
- RDP access will be available after installation (port 3389) - ensure proper firewall rules are in place

## Ubuntu 26.04 validation

The installer enables GDM and GNOME Remote Login on port 3389. Use the lab
username and the password in `~/.cnpg-rdp-password` for the RDP connection,
then the Ubuntu account password at the graphical login screen. Enable
`/gfx` with FreeRDP 3.

For automated local VM provisioning, set a user password first, then run
`CNPG_LAB_NONINTERACTIVE=true bash lab/install.sh`. This skips the proxy and
reboot prompts; reboot the guest afterwards. It does not print the password.

## Tool installation without Nix

Ubuntu packages provide Docker, curl, jq, kubectx/kubens, btop, bat, Git,
gettext and Python/PyYAML. `install-tools.sh` downloads kubectl, Kind, the CNPG
plugin, cmctl, Helm, k9s, lazydocker and stern from their official release sites.
Each download is checked against the publisher's SHA-256 list. All binaries go
to `/usr/local/bin`; versions are pinned in `tool-versions.env`.

To update, edit that version file and run `sudo bash lab/install-tools.sh`.
To upgrade an older Nix-based lab, rerun `lab/install.sh` to replace its managed
shell configuration. Nix is no longer used; it can be uninstalled separately
if no other projects need it.
