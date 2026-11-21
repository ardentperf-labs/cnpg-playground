#!/bin/bash
# Ubuntu 26.04 Desktop Setup Script
#
# This script is intended to run on a freshly installed Ubuntu 26.04 server. It
# installs a desktop environment for remote desktop access via RDP.
#
# WARNING: This script enables remote desktop access which may have security implications.
# Make sure to use strong passwords and consider firewall rules.
#

# Function to handle sudo command failures
sudo_cmd() {
    if ! sudo "$@"; then
        echo "✗ Sudo command failed: sudo $*"
        echo "Please check your sudo privileges and try again."
        exit 1
    fi
}

# Create a log file with timestamp
LOG_FILE="install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "******************************************************"
echo "**  CNPG Lab Desktop Setup Script                   **"
echo "**                                                  **"
echo "**  This script will install a desktop environment  **"
echo "**  for local use or for remote desktop access via  **"
echo "**  RDP. The script must be executed on a freshly   **"
echo "**  installed Ubuntu 26.04 Server which does NOT    **"
echo "**  have a desktop environment already installed.   **"
echo "**                                                  **"
echo "**  WARNING: This script enables remote desktop     **"
echo "**  access which may have security implications.    **"
echo "**  Make sure to use strong passwords and consider  **"
echo "**  firewall rules.                                 **"
echo "**                                                  **"
echo "**  You can re-run this script as many times as     **"
echo "**  needed, in case you run into errors or to       **"
echo "**  pull & apply script updates from GitHub.        **"
echo "**                                                  **"
echo "******************************************************"
echo .
echo "Log file: $LOG_FILE"
echo "You are logged in as: $USER"
echo "Starting script execution at: $(date)"
echo .

# Check if we're running on Ubuntu 26.04 Server
. /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 26.04 ]]; then
    echo "ERROR: This script is designed for Ubuntu 26.04 Server only."
    echo "Current OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo "Please run this script on Ubuntu 26.04 Server."
    exit 1
fi

# Check if this is a server installation (not desktop) - unless the desktop was already installed by this script
if [[ -f /etc/desktop-installed-by-cnpg-lab || -f /etc/cinnamon-desktop-installed-by-cnpg-lab ]]; then
    echo "✓ Lab desktop was already installed by this script. Proceeding with installation."
elif dpkg -l | awk '$1 == "ii" && $2 ~ /^xorg/ {found=1} END {exit !found}'; then
    echo "ERROR: This script is designed for Ubuntu 26.04 Server installations only."
    echo "Detected X11/Xorg installation. Please use Ubuntu 26.04 Server instead."
    exit 1
fi

echo "✓ Confirmed: Running on Ubuntu 26.04 Server"
echo .

# Check if the current user has a password set by examining /etc/shadow
echo "On cloud installations, no password is assigned to the default user. Needed for RDP remote access."
echo .
echo "WARNING: Remote desktop access may expose this system to unauthorized access attempts from the internet."
echo .
echo "Checking if user '$USER' has a password set..."
PASSWORD_NEEDED=false
if sudo_cmd grep "^$USER:" /etc/shadow | cut -d: -f2 | grep -q "^[!*]"; then
    echo "✗ User '$USER' does not have a password set (locked account)"
    PASSWORD_NEEDED=true
elif sudo_cmd grep "^$USER:" /etc/shadow | cut -d: -f2 | grep -q "^$"; then
    echo "✗ User '$USER' does not have a password set (empty password field)"
    PASSWORD_NEEDED=true
else
    echo "✓ User '$USER' has a password set"
fi

# Prompt for password if needed
USER_PASSWORD=""
if [ "$PASSWORD_NEEDED" = true ]; then
    if [[ "${CNPG_LAB_NONINTERACTIVE:-false}" == true ]]; then
        echo "ERROR: Set a login password with passwd before unattended installation."
        exit 1
    fi
    echo "Setting password for user '$USER'..."
    echo -n "Enter new password (input will be hidden): "
    read -s USER_PASSWORD
    echo
    echo -n "Confirm new password (input will be hidden): "
    read -s USER_PASSWORD_CONFIRM
    echo

    if [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
        echo "✗ Passwords do not match. Please run the script again."
        exit 1
    fi

    if [ -z "$USER_PASSWORD" ]; then
        echo "✗ Password cannot be empty. Please run the script again."
        exit 1
    fi

    echo "✓ Password will be set via Ansible"
fi
echo .

# Prompt the user to configure a proxy if needed for internet access. (Optional)
gateway=$(ip route | awk '/default/ {print $3}')
use_proxy=n
if [[ "${CNPG_LAB_NONINTERACTIVE:-false}" != true ]]; then
    read -r -p "Do you need to configure a proxy for internet access? [y/N]: " use_proxy
fi
use_proxy=${use_proxy,,}  # to lowercase

if [[ "$use_proxy" == "y" || "$use_proxy" == "yes" ]]; then
    read -p "Enter proxy IP address [${gateway}]: " proxy_ip
    proxy_ip=${proxy_ip:-$gateway}
    read -p "Enter proxy port [9000]: " proxy_port
    proxy_port=${proxy_port:-9000}
    echo "Proxy will be set to: http://$proxy_ip:$proxy_port/"
fi


# Add timestamp to the installation log
echo "Starting installation at: $(date)"
echo .

# Enable strict error handling for the installation phase
set -euo pipefail

# Set up error trap to print message on exit
trap 'echo "✗ Installation failed. Check the log file for details: $LOG_FILE"' EXIT

# Check if Ansible is installed and install if needed
echo "Checking for Ansible installation..."
if ! command -v ansible-playbook &> /dev/null; then
    echo "Ansible is not installed. Installing Ansible..."
    sudo_cmd apt-get update
    sudo_cmd apt-get install -y ansible-core
    echo "✓ Ansible installed successfully"
else
    echo "✓ Ansible is already installed"
fi
echo .

# Call Ansible playbook to perform the installation
echo "Running Ansible playbook for installation..."
cd "$(dirname "${BASH_SOURCE[0]}")"

# Prepare Ansible variables
ANSIBLE_VARS=""
if [[ "$use_proxy" == "y" || "$use_proxy" == "yes" ]]; then
    ANSIBLE_VARS="use_proxy=true proxy_ip=$proxy_ip proxy_port=$proxy_port"
fi

# Pass passwords over stdin, never in process arguments or Ansible logs.
if [ "$PASSWORD_NEEDED" = true ]; then
    printf '%s:%s\n' "$USER" "$USER_PASSWORD" | sudo chpasswd
    unset USER_PASSWORD USER_PASSWORD_CONFIRM
fi

# Run the Ansible playbook
ansible-playbook install-core.yml -i localhost, -c local --extra-vars "$ANSIBLE_VARS" | while read -r line; do echo "$(date +%H:%M:%S) $line"; done

echo "✓ Ansible playbook completed successfully"

# Remove the error trap since installation succeeded
trap - EXIT

# Inform the user that a reboot is required and prompts for confirmation
echo .
echo "Installation complete at: $(date)"
echo .
echo "You might need to restart the system for all changes to take effect. (In particular, the current user needs to pick up group changes.)"
echo .
echo "You can now connect via RDP as user '$USER' using the password in ~/.cnpg-rdp-password, then your Ubuntu password at the GNOME login screen."
echo .
if [[ "${CNPG_LAB_NONINTERACTIVE:-false}" == true ]]; then
    echo "Unattended install complete. Reboot before using the desktop."
    exit 0
fi
echo "Press Enter to reboot the system, or Ctrl+C to cancel..."
read -r
sudo_cmd reboot
