# Kubernetes deployment

Helm charts for deploying the retail-store-app to the EKS cluster provisioned
by [`../terraform`](../terraform/README.md). One chart per microservice, under
`charts/`, with per-environment values under `envs/`.

The app is deployed to two namespaces, `development` and `production`, both
managed by Terraform (see the [`rds`](../terraform/environments/rds/)
environment, which creates them and writes the `catalog-config` ConfigMap into
each).

## Layout

| Path                        | Purpose                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| `charts/catalog/`           | Catalog API chart (Deployment, Service, ServiceAccount, SecretProviderClass).  |
| `charts/ui/`                | UI chart (Deployment, Service, ConfigMap, ALB Ingress).                        |
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

- ECR image tag (immutable tags — bump the tag to deploy a new build)
- Replica count and resource sizing (production runs 2 replicas)
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

- A running EKS cluster (see [`../terraform`](../terraform/README.md) and the
  `configure_kubectl` output of the `eks` environment).
- `helm` 3.x installed locally.
- `docker` and the AWS CLI installed and authenticated.

## Build and push the images

The UI and test-tools images must be pushed to ECR before deployment. The
repositories use **immutable tags**, so each build must use a new tag.

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

## Publish the charts to ECR (OCI)

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

Install each release into its namespace from the published chart version,
combined with the matching environment values file:

```bash
# Development
helm install catalog \
  oci://692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/charts/catalog \
  --version 0.1.0 -n development -f k8s/envs/development/catalog-values.yaml
helm install ui \
  oci://692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/charts/ui \
  --version 0.1.0 -n development -f k8s/envs/development/ui-values.yaml

# Production
helm install catalog \
  oci://692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/charts/catalog \
  --version 0.1.0 -n production -f k8s/envs/production/catalog-values.yaml
helm install ui \
  oci://692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/charts/ui \
  --version 0.1.0 -n production -f k8s/envs/production/ui-values.yaml

kubectl wait --for=condition=available deploy/catalog deploy/ui -n development --timeout=180s
kubectl wait --for=condition=available deploy/catalog deploy/ui -n production --timeout=180s
kubectl get pods -A -l app.kubernetes.io/owner=retail-store-sample
```

Quick-start fallback: while iterating locally you can skip publishing and
install straight from the working tree by substituting the local chart path,
e.g. `helm install catalog k8s/charts/catalog -n development -f …`.

The catalog must be installed first if you point the UI at it: set
`RETAIL_UI_ENDPOINTS_CATALOG` in the environment's `ui-values.yaml`.

## Access

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

Publish a new chart version (see above), then upgrade each release to it:

```bash
helm upgrade catalog \
  oci://692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/charts/catalog \
  --version 0.2.0 -n production -f k8s/envs/production/catalog-values.yaml
```

Value-only changes (e.g. a new image tag in the environment's values file)
don't need a new chart version — re-run `helm upgrade` with the same chart and
the updated values file.

## Cleanup

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
