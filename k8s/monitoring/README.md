# Monitoring — Prometheus + Grafana

Satisfies the project requirement *"Create a Monitoring Dashboard using Grafana + Prometheus."*

The stack is [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack),
which bundles Prometheus, Grafana, `kube-state-metrics`, and `node-exporter`. It scrapes
the cluster with no change to the application image.

| File | Purpose |
|---|---|
| `values.yaml` | Helm values tuned for EKS Auto Mode (EBS storage, no Alertmanager, ClusterIP Grafana) |
| `namegen-dashboard.json` | Grafana dashboard for the namegen Deployment and the MongoDB StatefulSet |

## What the dashboard shows

Eight panels covering both workloads: available replicas, container restarts, running pod
count, MongoDB PVC utilisation (gauge and time series), CPU and memory per pod, and network
throughput for the app pods. A `namespace` variable at the top defaults to `namegen`.

Metrics come from cAdvisor and `kube-state-metrics`, so the panels are infrastructure-level.
The Express app exposes no `/metrics` endpoint, so request rate and latency per route are not
available. Adding `prom-client` to `server.js` and a `ServiceMonitor` would enable those; the
values file already sets `serviceMonitorSelectorNilUsesHelmValues: false` so a future
ServiceMonitor is picked up automatically.

## Prerequisites

The `ebs-sc` StorageClass must exist before installing. It is defined in `k8s/mongo.yaml`, so
deploy the app first (see [step 3 of the main README](../../README.md#3-first-image-build--manual-deploy)).

Without it, the Prometheus and Grafana PVCs sit in `Pending` forever — EKS Auto Mode ships no
usable StorageClass of its own.

## Install

1. Add the chart repository.

   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   ```

2. Install the stack into a dedicated namespace.

   Choose your own admin password. The chart default is `prom-operator`, and no password is
   committed to this repo.

   ```bash
   helm install monitoring prometheus-community/kube-prometheus-stack \
     --namespace monitoring --create-namespace \
     --values k8s/monitoring/values.yaml \
     --set grafana.adminPassword='<choose-a-password>'
   ```

3. Load the dashboard.

   The Grafana sidecar imports any ConfigMap labelled `grafana_dashboard=1`, so no manual UI
   import is needed.

   ```bash
   kubectl create configmap namegen-dashboard \
     --namespace monitoring \
     --from-file=k8s/monitoring/namegen-dashboard.json
   kubectl label configmap namegen-dashboard --namespace monitoring grafana_dashboard=1
   ```

4. Wait for every pod to become ready.

   ```bash
   kubectl wait --namespace monitoring --for=condition=ready pod --all --timeout=10m
   ```

5. Open Grafana.

   Grafana is a ClusterIP Service on purpose — exposing it would provision a second billable
   NLB and put a login page on the public internet.

   ```bash
   kubectl port-forward --namespace monitoring svc/monitoring-grafana 3000:80
   ```

   Browse to <http://localhost:3000> and sign in as `admin`. The dashboard is under
   **Dashboards → namegen — Application & MongoDB**.

## Screenshots to capture for submission

- The namegen dashboard with live data, after generating traffic against the NLB.
- The Prometheus targets page (`kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090`, then **Status → Targets**) showing targets `UP`.
- `kubectl get pods -n monitoring` showing the stack running.

## Cost

This stack is not free. It adds roughly 15Gi of EBS across two volumes and enough CPU and
memory that EKS Auto Mode will likely provision an additional node. Install it for the demo
and the screenshots, then remove it.

## Uninstall

CAUTION: `helm uninstall` does not delete PVCs. Their EBS volumes keep billing, and they
outlive the cluster. Delete them explicitly.

```bash
helm uninstall monitoring --namespace monitoring
kubectl delete pvc --all --namespace monitoring
kubectl delete namespace monitoring
```

The repo's `teardown.sh` performs these steps automatically before `terraform destroy`.
