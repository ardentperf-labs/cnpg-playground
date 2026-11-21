# GNOME Remote Login on Ubuntu 26.04.1 LTS

On the existing 4-vCPU, 16-GiB lab VM, Ubuntu Desktop Minimal, GDM and GNOME Remote Desktop ran GNOME Shell 50.1 on Wayland. The guest used a system RDP login with a TLS certificate and credentials configured through grdctl. The FreeRDP 3 client needed /gfx. Both xrdp and xrdp-sesman were masked to free port 3389.

- [GDM login over RDP](login.png). Logging out with gnome-session-quit ended session 17 and the client received ERRINFO_LOGOFF_BY_USER. A fresh RDP connection and GDM password login created Wayland session 25 on the same boot.
- [k9s over RDP](k9s.png). All three EU PostgreSQL pods had both containers ready. Mouse input and terminal commands worked.
- [Login after reboot](reboot.png). The terminal shows the lab greeting, GNOME version, Wayland session type, guest boot ID and color emoji.

A reboot exposed a startup race. GNOME Remote Desktop was active but had no listener because GDM had not yet exported its Displays object. On the next reboot the following guest systemd drop-in let the listener start automatically and the remote login succeeded. It lives at /etc/systemd/system/gnome-remote-desktop.service.d/gdm-ready.conf.

```ini
[Unit]
After=display-manager.service

[Service]
ExecStartPre=/bin/sh -c 'until busctl call org.gnome.DisplayManager /org/gnome/DisplayManager/Displays org.freedesktop.DBus.ObjectManager GetManagedObjects >/dev/null 2>&1; do sleep 1; done'
```

This was a desktop migration test on the working lab. At the time of this test the provisioning default was Cinnamon. An Ubuntu error-report dialog appeared on initial login and /var/crash contained a blueman-applet report.

The lab installer now configures GNOME Remote Login by default. On the existing
guest, the updated configuration survived reboot and accepted the generated
RDP credential followed by the Ubuntu password at GDM. The [installed desktop](installer.png)
shows the lab greeting, Wayland session and listener on TCP 3389.
