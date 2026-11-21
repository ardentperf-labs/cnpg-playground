#!/usr/bin/env bash
# Called as root by the desktop playbook. GDM takes over at reboot.
set -euo pipefail
user=$1
user_home=$2
grd_home=$(getent passwd gnome-remote-desktop | cut -d: -f6)
if dpkg-query -W -f='${db:Status-Status}' xrdp 2>/dev/null | grep -qx installed; then
    systemctl mask --now xrdp.service xrdp-sesman.service
fi
echo /usr/sbin/gdm3 > /etc/X11/default-display-manager
systemctl enable --force gdm3.service
if [[ ! -s $grd_home/rdp.crt || ! -s $grd_home/rdp.key ]]; then
    runuser -u gnome-remote-desktop -- openssl req -x509 -newkey rsa:3072 -nodes \
        -days 3650 -subj "/CN=$(hostname)" -keyout "$grd_home/rdp.key" -out "$grd_home/rdp.crt"
fi
grdctl --system rdp set-tls-key "$grd_home/rdp.key"
grdctl --system rdp set-tls-cert "$grd_home/rdp.crt"
runuser -u "$user" -- cat "$user_home/.cnpg-rdp-password" |
    grdctl --system rdp set-credentials "$user"
grdctl --system rdp enable
install -d /etc/systemd/system/gnome-remote-desktop.service.d
cat >/etc/systemd/system/gnome-remote-desktop.service.d/gdm-ready.conf <<'UNIT'
[Unit]
After=display-manager.service
[Service]
ExecStartPre=/bin/sh -c 'until busctl call org.gnome.DisplayManager /org/gnome/DisplayManager/Displays org.freedesktop.DBus.ObjectManager GetManagedObjects >/dev/null 2>&1; do sleep 1; done'
UNIT
systemctl daemon-reload
systemctl enable gnome-remote-desktop.service
