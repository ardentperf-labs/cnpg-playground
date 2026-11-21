# Local VM validation, 21 November 2026

The lab ran inside a local x86-64 KVM guest with 4 vCPUs, 16 GiB RAM and a 100 GiB disk. The guest booted Ubuntu Server 26.04.1 LTS. This run used upstream cnpg-playground commit `2e2bbb7`, Kubernetes 1.37.0, CloudNativePG 1.30.2 and PostgreSQL 18.7.

The guest initially tested the older installer. After purging the Nix packages, the updated installer completed, and a fresh playground deployed with the binaries in /usr/local/bin. The VM was reused for this migration test.

- [RDP terminal](02-rdp-direct-tools-clusters.png) shows the Ubuntu release, color emoji, installed command paths, absence of Nix on PATH, and six Ready nodes in each Kubernetes cluster. Mouse and keyboard input were sent through FreeRDP to Cinnamon.
- [CloudNativePG dashboard](03-rdp-grafana.png) shows live metrics in Firefox through the EU Grafana port forward. Grafana 13.2.4 serves its bundled Prometheus plugin with automatic plugin updates disabled.
- [Active Session History dashboard](04-rdp-ash.png) shows the EU primary's sampled wait events. Exercise 4 completed a scale-1, 30-second pgbench smoke run, reporting 165 ASH samples. A second pgbench run supplied additional traffic.

An EU write replicated to the US standby through the Barman Cloud setup. Reading the test row on US returned its value and confirmed `pg_is_in_recovery() = true`. The temporary table was then dropped.

Validation covers the local desktop, two-region playground, monitoring and ASH exercise. The Jepsen, mTLS, pgAdmin, Entra, Bluebox and orphan-PVC exercise walkthroughs, cloud launchers and ARM64 installation were not run end to end.
