# Kubernetes deployment

Helm charts for deploying the retail-store-app to the EKS cluster provisioned
by [`../terraform`](../terraform/README.md). One chart per microservice, under
`charts/`, with per-environment values under `envs/`.

Deployments are **managed by ArgoCD** (installed by the [`eks`
Terraform environment](../terraform/environments/eks/)). ArgoCD watches this
repo and syncs each chart into the target cluster namespace:

```
push to main → CI builds+pushes images → CI writes the image tag into
               k8s/envs/production/*-values.yaml and commits
             → ArgoCD syncs catalog/ui into the production namespace

push to dev  → same, but k8s/envs/development/* and the development namespace
```

The ArgoCD `Application` resources (one per service/environment) and the
ArgoCD UI ingress live in `argocd/` and are applied by Terraform via
`kubectl_manifest`. The app is deployed to two namespaces, `development` and
`production`, both managed by Terraform (see the [`rds`](../terraform/environments/rds/)
environment, which creates them and writes the `catalog-config` ConfigMap into
each).

## Layout

| Path                        | Purpose                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| `charts/catalog/`           | Catalog API chart (Deployment, Service, ServiceAccount, SecretProviderClass).  |
| `charts/ui/`                | UI chart (Deployment, Service, ConfigMap, ALB Ingress).                        |
| `argocd/`                   | ArgoCD `Application` manifests (catalog/ui × dev/prod) + ALB ingress for the ArgoCD UI. Applied by Terraform. |
| `observability/`            | ADOT Collector + ClusterIP service + RBAC: traces → AWS X-Ray, logs → CloudWatch Logs, metrics → AWS Managed Prometheus (see the Observability section). |
| `envs/development/`         | Values overrides for the development namespace.                                |
| `envs/production/`          | Values overrides for the production namespace.                                 |
| `namespace*.yaml`           | **Reference only** — namespaces are created by Terraform.                      |
| `catalog/`, `ui/`           | **Reference only** — hand-written manifests from the previous kubectl-based workflow. Do not apply. |
| `test/`                     | Debug pod (aws-cli, curl, nslookup, mysql) and its service account.            |

The manifests under `catalog/`, `ui/`, and `namespace*.yaml` are kept as a
historical reference showing how these resources were applied with
`kubectl apply` before the move to Helm and Terraform-managed namespaces.

### Chart configuration

Base defaults live in each chart's `values.yaml`; environment-specific
overrides live in `envs/<environment>/<chart>-values.yaml`:

- ECR image tag (immutable tags — bump the tag to deploy a new build; the CI
  pipeline rewrites it to the commit's short SHA for ArgoCD to roll out)
- Replica count and resource sizing (production runs 3 replicas)
- UI endpoint wiring and theme (`config`)
- ALB ingress annotations (`ui.ingress.annotations`)
- Probes, security context

Resource names are fixed (`catalog`, `ui`, `catalog-sa`, `catalog-app`,
`ui-config`) so the Terraform-managed Pod Identity associations for
`catalog-sa` and the `catalog-config` ConfigMaps written by the
[`rds`](../terraform/environments/rds/) environment keep working regardless of
Helm release names. Both environments share the same RDS instance and Secrets
Manager secret (`retail-store/catalog/db2`).

## Prerequisites

- A running EKS cluster with ArgoCD installed (see [`../terraform`](../terraform/README.md)
  and the `configure_kubectl` output of the `eks` environment).
- `aws` CLI + `kubectl` configured against the cluster to inspect/verify
  deployments. `helm` is only needed for out-of-band/fallback management —
  ArgoCD is the source of truth.

## Build and push the images

In normal operation the CI pipeline (`.github/workflows/build-images.yml`)
builds and pushes the `catalog`/`ui` images on every push to `main`/`dev`. The
commands below are the equivalent manual flow (e.g. for the `test-tools`
image, which CI does not build). The ECR repositories use **immutable tags**,
so each build must use a new tag.

```bash
# 1. Authenticate docker with the ECR registry
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com

# 2. Build and push the UI image
docker build -t 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/ui:0.0.1 src/ui
docker push 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/ui:0.0.1

# 3. Build and push the test-tools image
docker build -t 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/test-tools:latest src/test
docker push 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/test-tools:latest
```

## Update UI content

All UI content (templates, CSS, images, product data, labels) lives in
`src/ui/src/main/resources/` and is baked into the Docker image at build time.
To push a content change to the cluster:

1. Edit the relevant files under `src/ui/src/main/resources/`:
   - `templates/*.html` — page layout and content
   - `static/assets/css/` — styles and themes
   - `static/assets/img/` — hero, product, and avatar images
   - `data/products.json` — product catalog entries
   - `lang/messages.properties` — UI text labels

2. Push the change to `main` (or `dev`). The CI pipeline
   (`.github/workflows/build-images.yml`) builds and pushes a new image tagged
   with the short SHA, rewrites `image.tag` in the matching
   `k8s/envs/<env>/<service>-values.yaml`, and commits it back. ArgoCD then
   detects the new commit and rolls the service out — no manual `helm`
   command needed.

The `maxSurge: 0` rolling update strategy terminates old pods before creating
new ones, so the deployment completes within the existing NodePool capacity
without provisioning additional nodes.

## Publish the charts to ECR (OCI)

> **Legacy / optional:** the current ArgoCD setup installs straight from the
> working tree of this repo (`spec.source.path` → `k8s/charts/<service>`), so
> publishing to ECR is no longer required to deploy. Keep the section below
> only if you want OCI-versioned chart artifacts for reproducibility.

Charts are stored in ECR as OCI artifacts, one repository per chart
(`charts/catalog`, `charts/ui`, provisioned by the
[`ecr`](../terraform/environments/ecr/) Terraform environment). Publishing a
versioned chart makes deployments reproducible without cloning this repo.

To publish a new version, bump `version` in the chart's `Chart.yaml` first —
ECR repositories are immutable — then package and push:

```bash
# 1. Authenticate helm with ECR
aws ecr get-login-password --region ap-southeast-1 | \
  helm registry login --username AWS --password-stdin 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com

# 2. Package and push each chart
helm package k8s/charts/catalog
helm push catalog-0.1.0.tgz oci://692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/charts

helm package k8s/charts/ui
helm push ui-0.1.0.tgz oci://692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/charts
```

## Deploy

Deploys are driven by **ArgoCD** — nothing is applied to the cluster manually.
Each service/environment pair has an ArgoCD `Application` defined in
[`argocd/`](argocd/):

| Application | Repo revision | Chart | Values | Namespace |
| ----------- | ------------- | ----- | ------ | --------- |
| `catalog-production` | `main` | `k8s/charts/catalog` | `envs/production/catalog-values.yaml` | `production` |
| `ui-production`      | `main` | `k8s/charts/ui`      | `envs/production/ui-values.yaml`      | `production` |
| `catalog-development`| `dev`  | `k8s/charts/catalog` | `envs/development/catalog-values.yaml`| `development` |
| `ui-development`     | `dev`  | `k8s/charts/ui`      | `envs/development/ui-values.yaml`     | `development` |

To ship a change, push to the matching branch — the CI pipeline builds & pushes
the images, records the tag in the env values, and commits it. ArgoCD
auto-syncs (`prune: true`, `selfHeal: true`) and rolls the release out:

```bash
git push origin main        # → production
git push origin dev         # → development
```

Out-of-band fallback (e.g. ArgoCD is down): install straight from the working
tree with the same values file, e.g.
`helm upgrade -i catalog k8s/charts/catalog -n production -f k8s/envs/production/catalog-values.yaml --set image.tag=<sha>`.

Verification:

```bash
argocd app list -o table
argocd app get catalog-production
kubectl get pods -n production -l app.kubernetes.io/owner=retail-store-sample
```

The catalog must be present before the UI can reach it: the environment's
`ui-values.yaml` points `RETAIL_UI_ENDPOINTS_CATALOG` at `http://catalog`.

## Access

### ArgoCD UI

The ArgoCD server is exposed on an internet-facing ALB (see
[`argocd/ingress.yaml`](argocd/ingress.yaml)). Get the URL and the initial
`admin` password:

```bash
# 1. UI address (ALB DNS name)
kubectl get ingress argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# e.g. k8s-argocd-argocdse-xxxx.elb.amazonaws.com — open it with http://

# 2. Initial admin password (auto-generated on install)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

> The initial password is stored in the `argocd-initial-admin-secret` Secret
> and is auto-generated; it is only meant to be used once. After your first
> login, change it (see below).

Change the admin password (via the CLI — also how the rest of this README's
`argocd` commands authenticate):

```bash
argocd login <ALB-address> --username admin --insecure
argocd account update-password
```

If `argocd` is not installed locally:

```bash
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

### App endpoints

Each namespace's UI Ingress provisions its own internet-facing ALB (created by
the AWS Load Balancer Controller). After deploying:

```bash
kubectl get ingress ui -n development
kubectl get ingress ui -n production
```

Copy the `ADDRESS` column (the ALB DNS name) and open it in your browser:

```
http://k8s-default-ui-xxxxxxxxxx-xxxxxxxxxx.ap-southeast-1.elb.amazonaws.com
```

The ALB takes a few minutes to become healthy after the first deployment.

## Upgrade

- **Image-only change:** push to the branch. CI builds/pushes, rewrites the
  image tag in `k8s/envs/<env>/<service>-values.yaml`, and commits; ArgoCD
  syncs it. No chart version bump or manual command.
- **Chart change:** commit the change to `k8s/charts/<service>` and push.
  ArgoCD picks it up on the next sync (bump the chart `version` to make the
  rollout visible in the UI).

Out-of-band fallback, same as before:
`helm upgrade catalog k8s/charts/catalog -n production -f k8s/envs/production/catalog-values.yaml`

## Cleanup

To delete a release, remove (or disable) the matching ArgoCD `Application` in
[`argocd/`](argocd/) — e.g. the `catalog-development` Application for the dev
catalog — and let it prune. As a fallback, `helm uninstall` straight from the
cluster:

```bash
helm uninstall ui catalog -n development
helm uninstall ui catalog -n production
```

This removes the deployments, services, configmaps, ingress, service account,
and secret provider class. The Terraform-provisioned infrastructure (EKS, RDS,
IAM roles) is unaffected.

## Next steps

- Add charts for cart, orders, and checkout following the same pattern once
  their persistence/messaging backends are decided.

## Observability — Distributed Tracing (AWS X-Ray), Logs (CloudWatch), Metrics (AMP)

Services export OpenTelemetry (OTLP) traces and container logs, plus
Prometheus metrics the collector scrapes. Two collectors are used:
**`adot-collector`** is a single `Deployment` that forwards **traces to AWS
X-Ray** and **metrics to AWS Managed Prometheus (AMP)** exactly once (a
single central point keeps tail-sampling decisions accurate and avoids
duplicate AMP ingestion). **`log-agent`** is a per-node `DaemonSet` that
ships each node's container **logs to CloudWatch Logs**. Both are ADOT
collectors installed by the ADOT EKS add-on (managed by Terraform) and
deployed via `OpenTelemetryCollector` custom resources.

```
[app pod: catalog] ─OTLP http:4318─┐
[app pod: ui]     ─OTLP http:4318─┼─▶ adot-collector.aws-otel-eks:4318 (ClusterIP)
                                  │         │
                                  ▼         ▼
               adot-collector (Deployment, x1)    log-agent (DaemonSet, per spot node)
               traces: filter → memory_limiter    logs: filelog (tail /var/log/pods)
                       → groupbytrace                  → filter/log-noise
                       → tail_sampling                 → resourcedetection
                       → k8sattributes → batch         → k8sattributes
               metrics: prometheus (scrape app         → resource/log-stream
                       + kubelet cAdvisor → batch      → batch
                       /metrics)            │
                                  │         │  (Pod Identity: eks-adot-collector /
                                  │         │   AWSXRayDaemonWriteAccess
                                  │         │   + CloudWatchAgentServerPolicy
                                  │         │   + aps:RemoteWrite)
              traces──────▶│         │
              metrics─────▶│         │
              logs────────▶│         ▼
                                  │   AWS X-Ray  /  AMP  /  CloudWatch Logs
```

### Components

| Path                                                                        | Purpose                                                           |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `terraform/modules/eks/main.tf`                                             | ADOT add-on, collector IAM role (`AWSXRayDaemonWriteAccess` + `CloudWatchAgentServerPolicy` + inline `aps:RemoteWrite`), `aws_prometheus_workspace` and the EKS Pod Identity association for `aws-otel-collector` / `aws-otel-eks`. |
| `k8s/observability/namespace.yaml`                                          | `aws-otel-eks` namespace.                                         |
| `k8s/observability/serviceaccount.yaml`                                     | `aws-otel-collector` service account (role attached via Pod Identity, no annotation needed). |
| `k8s/observability/rbac.yaml`                                               | ClusterRole/Binding for the collector's K8s service discovery (endpoints/services/pods/namespaces/nodes) and `nodes/proxy` (kubelet cAdvisor). |
| `k8s/observability/collector.yaml`                                          | `OpenTelemetryCollector` CR (`adot-collector`) — single Deployment with the cost-control traces pipeline and the metrics→AMP pipeline. |
| `k8s/observability/log-agent.yaml`                                          | `OpenTelemetryCollector` CR (`log-agent`) — per-node DaemonSet logs→CloudWatch pipeline (spot nodes only).                 |
| `k8s/observability/service.yaml`                                            | ClusterIP `adot-collector` exposing 4317 (gRPC) / 4318 (HTTP).     |

Each app chart (`k8s/charts/{catalog,ui}`) ships an `opentelemetry` value
block; when `opentelemetry.enabled: true` the deployment template injects the
standard OTLP env vars (`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`,
etc.). The Java `ui` service additionally sets
`OTEL_JAVA_GLOBAL_AUTOCONFIGURE_ENABLED=true`. Both environments enable it in
`k8s/envs/*/…-values.yaml`. Each chart's Service also ships the
`prometheus.io/scrape` + `prometheus.io/path` annotations used for metrics
service discovery.

### Cost control (why tracing won't break the bank)

X-Ray bills per trace recorded/retrieved and by segment storage. Without
controls, the busiest source of noise is **Kubernetes health/probe traffic**
(`/health`, `/actuator/health/*`) fired every ~10s per pod, plus ALB
`ELB-HealthChecker` probes. The collector pipeline drops this and samples the
rest:

```
filter/drop-noise   drop /health, /ready, /actuator/health/* and kube-probe/ELB user agents
memory_limiter      bound memory before tail-sampling buffers traces
groupbytrace        gather all spans of a trace for a per-trace decision
tail_sampling       keep 100% ERROR traces + 100% slow (>1s) + 5% happy-path
k8sattributes       enrich with pod/deployment/namespace
batch               efficient batching to X-Ray
```

Tune the numbers in `k8s/observability/collector.yaml` (the
`tail_sampling` → `sample-happy-path` `sampling_percentage`, and
`keep-slow` → `threshold_ms`) to match your cost appetite.

> **Note on tail sampling placement:** tail sampling needs all spans of a
> trace in one collector to decide accurately. Traces are therefore handled by
> the single central `adot-collector` Deployment, not the DaemonSet — the two
> kinds of workloads coexist, and the logs-only DaemonSet stays per-node.

### Logs — container logs to CloudWatch Logs

A **per-node DaemonSet** (`log-agent`) tails each node's `/var/log/pods` and
ships the app services' stdout/stderr to a single **CloudWatch Logs group**
`/retail-store/application`, with **one log stream per (service, node)**
(`catalog-<node>`, `ui-<node>`) and a **7-day retention**
(`log_retention: 7`).

```
[log-agent DaemonSet pod on each node]
filelog (tail /var/log/pods/*/*/*.log on the local node)
  → filter/log-noise     drop anything not in the development|production namespaces
  → resourcedetection    add region / account / cluster / platform
  → k8sattributes        add pod / deployment / node / container
  → resource/log-stream  map container name → service.name (drives the stream)
  → batch
  → awscloudwatchlogs    group /retail-store/application, stream {ServiceName}-{NodeName}
```

Notes:

- **Why a DaemonSet and not the central collector:** a Deployment collector
  only sees the logs of pods scheduled to its own node. To tail *all* app pods
  (catalog, ui, checkout, …) whichever node they land on, one filelog receiver
  per node is needed — hence one collector pod per node.
- The DaemonSet is scheduled with `nodeSelector: karpenter.sh/capacity-type:
  spot`. The app namespaces are spot-pinned, and the managed nodes sit at the
  t3.small `maxPods` ceiling, so nothing needs logs on the on-demand nodes.
- **Root-only files:** kubelet writes each container's log under
  `/var/log/pods` as `root:root` mode 640, so `log-agent` runs with
  `runAsUser: 0` and mounts `/var/log/pods` (and `/var/lib/docker/containers`)
  read-only. Without this, filelog silently matches nothing.
- The stream name embeds the node name (`{NodeName}` → `k8s.node.name`)
  because the exporter only substitutes a fixed set of placeholders *and*
  multiple per-node collectors writing the same `{ServiceName}` stream would
  race on CloudWatch sequence tokens.
- The `filelog` receiver uses the `container` parser operator, which
  auto-detects the Docker / CRI-O / containerd format (EKS AL2023 uses
  containerd) and extracts `k8s.namespace.name`, `k8s.pod.name`,
  `k8s.container.name`, etc. from the log file path.
- `start_at: end` means historical logs are **not** back-filled on first
  deploy (change to `beginning` to backfill). Each collector's own logs are
  excluded (see the `exclude` globs in `k8s/observability/log-agent.yaml`).
- Cost control: only the `development` and `production` namespaces are kept,
  so `kube-system` / platform noise never reaches CloudWatch. Adjust the
  include/exclude patterns and filters in
  `k8s/observability/log-agent.yaml` for a wider or narrower scope.
- CloudWatch Logs bills per GB ingested and by storage; the 7-day retention
  bounds storage cost. To reduce ingestion further, tighten the
  `filelog` filters.

### Metrics — Prometheus to AWS Managed Prometheus (AMP)

The collector's `prometheus` receiver scrapes Prometheus `/metrics` endpoints
and the `prometheusremotewrite` exporter uploads them to the **AMP workspace**
created by Terraform (`aws_prometheus_workspace.amp` in the `eks` module),
signing each request with SigV4 via the `sigv4auth` extension (the collector's
Pod Identity role, granted `aps:RemoteWrite`).

```
scrape:  catalog /metrics            (Go / ginprometheus)
         ui      /actuator/prometheus (Spring Boot / Micrometer)
         kubelet :10250/metrics/cadvisor (via API server proxy) → node + container
  → prometheus receiver (kubernetes_sd_configs: endpoints + node)
  → batch/metrics
  → prometheusremotewrite → AMP workspace (150d retention)
```

- **App metrics** are discovered via Kubernetes service discovery using the
  `prometheus.io/scrape` / `prometheus.io/path` annotations on the `catalog`
  and `ui` Services (see chart `service.annotations`).
- **Node/container metrics** come from kubelet's cAdvisor endpoint, reached
  through the API server proxy (`/api/v1/nodes/<node>/proxy/metrics/cadvisor`).
  The collector needs the RBAC in `k8s/observability/rbac.yaml`
  (`list/watch` on endpoints/services/pods/namespaces/nodes plus `nodes/proxy`).
- **Cost control (AMP bills per ingested sample + storage):** targets are
  scoped tight (only `catalog`/`ui` in `development`/`production`, plus the
  nodes), `scrape_interval` is `30s` (not 15s), and `sample_limit` caps each
  target. The workspace `data_retention_days` is `150` (the free-tier default);
  lower it if you want cheaper storage. See `k8s/observability/collector.yaml`
  to tune.

#### Wire up the remote-write endpoint

The remote-write URL in `k8s/observability/collector.yaml` points at the AMP
workspace created by Terraform. After (re)creating the workspace, read the URL
from the `eks` environment output and update `prometheusremotewrite.endpoint`:

```bash
cd terraform/environments/eks
terraform output amp_remote_write_url
# e.g. https://aps-workspaces.ap-southeast-1.amazonaws.com/workspaces/ws-xxxx/api/v1/remote_write
```

> Note: the app services keep `OTEL_METRICS_EXPORTER: none` — the collector
> **scrapes** their native Prometheus endpoints, so the app SDKs don't need to
> emit OTLP metrics. To query the data directly (before any Grafana), use the
> AMP workspace query editor or:
> ```bash
> awscurl --service="aps" --region ap-southeast-1 \
>   "https://<workspace-endpoint>/api/v1/query?query=up"
> ```

### Deploy

1. **Install the ADOT add-on + collector IAM** (one time, via Terraform):
   ```bash
   cd terraform/environments/eks
   terraform apply
   ```
2. **Apply the collector manifests**:
   ```bash
   kubectl apply -f k8s/observability/
   kubectl -n aws-otel-eks rollout status deploy/adot-collector-collector
   kubectl -n aws-otel-eks rollout status daemonset/log-agent-collector
   kubectl -n aws-otel-eks get pods -o wide
   ```
3. **Deploy/upgrade the apps** with tracing enabled (already on by default in
   the env overrides): push `main` / `dev` and let ArgoCD sync, or use the
   out-of-band fallback:
   ```bash
   helm upgrade -i catalog k8s/charts/catalog -n development -f k8s/envs/development/catalog-values.yaml
   helm upgrade -i ui k8s/charts/ui -n development -f k8s/envs/development/ui-values.yaml
   # repeat for production
   ```
4. Generate traffic (hit the UI ALB), then open the **AWS X-Ray console →
   Traces** (or **CloudWatch → Application Signals**) to see the service map,
   and **CloudWatch → Log groups → `/retail-store/application`** to see the
   `catalog` / `ui` log streams. For metrics, open the **AMP workspace** in the
   console and run a query (e.g. `up`, `container_cpu_usage_seconds_total`).

### Troubleshooting

- **No traces in X-Ray / no metrics in AMP:** verify the central collector can
  reach X-Ray/AMP — check its Pod Identity role association
  (`AWSXRayDaemonWriteAccess`, `aps:RemoteWrite`):
  ```bash
  kubectl -n aws-otel-eks logs deploy/adot-collector-collector
  ```
- **No logs in CloudWatch:** confirm the `log-agent` DaemonSet is running on
  the nodes hosting app pods and can read `/var/log/pods` (needs
  `runAsUser: 0` — see above) and write to CloudWatch (needs
  `CloudWatchAgentServerPolicy`). The log group is created automatically on
  first write:
  ```bash
  kubectl -n aws-otel-eks logs daemonset/log-agent-collector
  aws logs describe-log-groups --log-group-name-prefix /retail-store/application
  ```
- **No metrics in AMP:** confirm the remote-write endpoint is the real
  workspace URL (not a placeholder), the collector role has `aps:RemoteWrite`,
  and the `k8s/observability/rbac.yaml` role is bound. Then query AMP:
  ```bash
  kubectl -n aws-otel-eks logs deploy/adot-collector-collector
  aws amp query-workspace --workspace-id <id> --query 'up'
  ```
- **Connection refused from apps:** confirm the app pods can resolve
  `adot-collector.aws-otel-eks` (the ClusterIP service targets the central
  collector Deployment pod; use the FQDN from cross-namespace pods).
- **Wanted more/fewer traces, logs or metrics:** adjust the sampling /
  size filter policies in `k8s/observability/collector.yaml` and the log
  filters in `k8s/observability/log-agent.yaml`, then re-apply.

## Karpenter Spot Instances

Karpenter dynamically provisions spot EC2 instances for unscheduled pods.
The managed node group (on-demand `t3.small`) remains as a fallback for
critical workloads. The spot NodePool uses `t3.micro` and `t3.small` instances across all three
AZs with a total resource limit of 16 CPU and 24Gi memory. (`t3.medium` is
excluded because it is not eligible for the AWS Free Tier.)

Production workloads are protected by Pod Disruption Budgets (`minAvailable: 1`)
so Karpenter respects availability during spot interruptions and node consolidation.

### Monitoring

Open four terminals to observe Karpenter behavior in real time:

**Terminal 1 — Karpenter Logs (filtered)**

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f | \
  grep -E "interrupt|cordon|drain"
```

**Terminal 2 — Node Status**

```bash
kubectl get nodes -l karpenter.sh/capacity-type=spot -w
```

**Terminal 3 — Pod Status**

```bash
kubectl get pods -l app=spot-test -o wide -w
```

**Terminal 4 — NodeClaims**

```bash
kubectl get nodeclaims -w
```
