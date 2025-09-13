# Talos-based deployment

This directory contains sample resources for running the Nextcloud server on [Talos Linux](https://www.talos.dev/).
Talos provides a minimal, immutable OS for Kubernetes clusters. Workloads are deployed via Helm charts.

## Generate cluster configuration

Use `talosctl` to generate the cluster configuration and apply the patch in `nextcloud-patch.yaml` to set
node-specific options like the install disk and hostname:

```bash
talosctl gen config nextcloud https://<CONTROL_PLANE_IP>:6443 \
  --config-patch @talos/nextcloud-patch.yaml \
  --out-dir clusterconfig
```

Apply the generated configuration to your nodes and bootstrap the control plane:

```bash
talosctl apply-config --insecure --nodes <NODE_IP> --file clusterconfig/controlplane.yaml
# for worker nodes use clusterconfig/worker.yaml
talosctl bootstrap --nodes <CONTROL_PLANE_IP>
```

## Deploy Nextcloud via Helm

The Helm chart under `charts/nextcloud-stack` wraps the Bitnami Nextcloud chart with defaults suitable for Talos.
Install it once the Kubernetes cluster is ready:

```bash
helm dependency update charts/nextcloud-stack
helm install nextcloud charts/nextcloud-stack
```

The default `values.yaml` enables PostgreSQL and Redis subcharts and exposes Nextcloud through an ingress at
`nextcloud.example.com`. Adjust the values file to match your environment.

To swap the default Apache web server for NGINX, set `nextcloud.webserver.type` to `nginx` in `values.yaml`.
Outbound email can be handled by a lightweight `msmtp` agent by configuring `nextcloud.smtp.host` accordingly.
For persistent storage backed by ZFS, create a dataset and expose it via a Kubernetes PersistentVolumeClaim, then reference it using `nextcloud.persistence.existingClaim`.
