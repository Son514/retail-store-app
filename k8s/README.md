# Kubernetes manifests

Hand-written Kubernetes manifests for deploying the retail-store-app to the
EKS cluster provisioned by [`../terraform`](../terraform/README.md). These are
an alternative to the per-service Helm charts under `src/*/chart`.

All resources are deployed to the `development` namespace.

## Layout

| Path                       | Purpose                                                        |
| -------------------------- | -------------------------------------------------------------- |
| `namespace.yaml`           | `development` namespace shared by all services.                |
| `ui/deployment.yaml`       | UI deployment (1 replica, probes, security context).           |
| `ui/service.yaml`          | ClusterIP service exposing the UI on port 80.                  |
| `ui/configmap.yaml`        | UI environment configuration (`ui-config`).                    |
| `catalog/deployment.yaml`  | Catalog deployment (1 replica, readiness probe, security context). |
| `catalog/service.yaml`     | ClusterIP service exposing the catalog on port 80.             |
| `catalog/configmap.yaml`   | Catalog environment configuration (`catalog-config`).         |
| `catalog/mysql/statefulset.yaml` | MySQL StatefulSet (1 replica, ephemeral storage).         |
| `catalog/mysql/service.yaml`     | Headless service exposing MySQL on port 3306.               |
| `catalog/mysql/secret.yaml`      | Database credentials (`catalog-db`).                       |

## Prerequisites

- A running EKS cluster (see [`../terraform`](../terraform/README.md) and the
  `configure_kubectl` output of the `eks` environment).
- `kubectl` configured with the cluster context.
- `docker` and the AWS CLI installed and authenticated.

## Build and push the image

The UI image must be pushed to ECR before the deployment can pull it. The
repositories use **immutable tags**, so each build must use a new tag.

```bash
# 1. Authenticate docker with the ECR registry
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com

# 2. Build the UI image
docker build -t 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/ui:0.0.1 src/ui

# 3. Push it
docker push 692797214517.dkr.ecr.ap-southeast-1.amazonaws.com/ui:0.0.1
```

## Deploy

```bash
kubectl apply -f k8s/

kubectl wait --for=condition=available deploy/ui -n development --timeout=120s
kubectl get pods -n development
```

## Access

There is no Ingress or load balancer yet, so forward the service to your local
machine:

```bash
kubectl port-forward -n development svc/ui 8080:80
```

Then open <http://localhost:8080>.

## Update the image

Change the tag in `k8s/ui/deployment.yaml` (immutable tags require a new tag)
and re-apply:

```bash
kubectl apply -f k8s/ui/
```

## Cleanup

```bash
kubectl delete -f k8s/
```

## Next steps

- Wire the backend endpoints by adding `RETAIL_UI_ENDPOINTS_*` entries to
  `k8s/ui/configmap.yaml` once catalog, cart, and orders are deployed
  (e.g. `RETAIL_UI_ENDPOINTS_CATALOG: http://catalog:8080`).
- Add an Ingress or LoadBalancer service to expose the UI externally.
