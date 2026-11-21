# Clean Ubuntu Server rebuild, 21 November 2026

Exercise 1 provisioned a fresh Ubuntu Server 26.04.1 LTS guest on local x86-64 KVM with 4 vCPUs, 16 GiB RAM and a 100 GiB disk. The previous guest disk was deleted. Both the host and guest cloned the published lab branch. The guest started at `055fed5`. The documented installer finished in 8 minutes 29 seconds, with zero failed Ansible tasks, and rebooted. Docker and xrdp started automatically. The lab tools ran from /usr/local/bin. Nix was absent from PATH.

Cloud-init reported a recoverable warning about unlocking the account before assigning its password. The generated password worked for a Cinnamon login through FreeRDP. During the same run the installer reapplied the restored shell greeting. A new interactive Bash tab printed it once. A noninteractive Bash invocation produced no greeting.

- [New terminal greeting](clean-rdp-greeting.png) shows the original diagram and command reference, updated for RustFS and the current EU/US startup commands.
- [k9s](clean-rdp-k9s.png) shows three Running EU PostgreSQL pods, each with two Ready containers and zero restarts.
- [ASH dashboard](clean-rdp-ash.png) shows the imported dashboard in the guest's Firefox browser. Both panels display data from pg-eu-1 during the default pgbench workload.

## Playground and monitoring

Exercise 2 created six Ready Kubernetes nodes in each region. The SSH driver disconnected during the EU rollout. Repeating the documented `demo/setup.sh eu us` command completed successfully on the same cluster. Both CloudNativePG clusters reached three Ready PostgreSQL instances. After a WAL switch, an EU test row was readable on the US standby, where `pg_is_in_recovery()` returned true. The test table was dropped.

Installing monitoring after the demo initially left Grafana's ASH panels empty. The demo only created its PodMonitor when the monitoring CRD already existed. The corrected monitoring installer applies the same PodMonitor template when it finds an existing demo cluster. Rerunning it created the missing monitors in both regions. The US monitoring stack was then removed and reinstalled with the corrected script to exercise the fresh install order.

Exercise 4 used its documented automation with default pgbench settings. At scale 10, four clients completed 29,938 transactions in 300 seconds with zero failures (99.80 TPS). The SQL check counted 732 ASH samples. Prometheus reported three CNPG collectors in each region after the US monitoring reinstall. In Firefox over RDP, the dashboard JSON was uploaded and the DS_PROMETHEUS datasource selected. The EU Grafana port forward was the command printed by the monitoring installer. The walkthrough now includes that command.

This run covers local KVM provisioning, Cinnamon RDP, Exercises 1 and 2 setup, monitoring, and the Exercise 4 automation and dashboard import. The other exercises and GNOME desktop are outside this run.
