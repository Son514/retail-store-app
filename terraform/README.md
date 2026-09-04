# Terraform — AWS infrastructure

Modular Terraform for the retail-store-app AWS infrastructure (region `ap-southeast-1`).

## Layout

| Path                         | Purpose                                                                  |
| ---------------------------- | ------------------------------------------------------------------------ |
| `bootstrap/`                 | Creates the S3 bucket that stores remote state. State is local.           |
| `environments/network/`      | VPC stack (subnets, IGW, NAT, route tables); remote state in the bucket.  |
| `environments/eks/`          | EKS cluster + managed node group, using the network's private subnets.    |
| `environments/ecr/`          | ECR repositories for the microservices; remote state in the bucket.       |
| `environments/rds/`          | RDS MySQL + app namespaces/catalog ConfigMap; remote state in the bucket.  |
| `modules/vpc/`               | Reusable VPC module.                                                      |
| `modules/eks/`               | Reusable hand-written EKS module (IAM, cluster, SG, node group, Pod Identity). |
| `modules/ecr/`               | Reusable ECR module (repositories + lifecycle policy).                    |
State locking uses S3 native locking (`use_lockfile = true`) — **no DynamoDB**.
Requires Terraform >= 1.10.

## Apply order

```bash
# 1. Bootstrap: create the state bucket (once)
cd bootstrap
terraform init && terraform apply

# 2. Network: VPC stack, state stored in the bucket
cd ../environments/network
terraform init && terraform plan && terraform apply

# 3. ECR: microservice repositories (order-independent — any time after init)
cd ../environments/ecr
terraform init && terraform plan && terraform apply

# 4. EKS: cluster + node group (takes ~10-15 min)
#    Requires the shared.tfvars setup (see "Configuration" below)
#    Also installs the ADOT add-on + collector IAM (AWS X-Ray, CloudWatch Logs,
#    AMP) + the AMP workspace (see "Observability" below).
cd ../environments/eks
terraform init && terraform plan && terraform apply

# 5. RDS: database + namespaces + catalog ConfigMap
#    MUST run after EKS — reads the cluster endpoint, CA and security group
#    from its remote state
cd ../environments/rds
terraform init && terraform plan && terraform apply
```

kubectl access for helm/kubectl work (Terraform itself does not need it):

```bash
aws eks update-kubeconfig --name retail-store --region ap-southeast-1
```

Application deploys (images, charts, helm releases): see `../k8s/README.md`.

## Configuration (`shared.tfvars`)

All deployment-specific values live in **one gitignored file**,
`environments/shared.tfvars` (template: `shared.tfvars.example`). Every
environment consumes it via a single `config` object variable plus a
symlink, so one edit point serves all four stacks:

```bash
cd environments
cp shared.tfvars.example shared.tfvars            # once per machine
ln -sf ../shared.tfvars network/terraform.tfvars
ln -sf ../shared.tfvars eks/terraform.tfvars
ln -sf ../shared.tfvars rds/terraform.tfvars
ln -sf ../shared.tfvars ecr/terraform.tfvars
```

`terraform plan` / `apply` auto-load each directory's symlinked
`terraform.tfvars` — no flags needed.

Why a single object instead of plain variables: the four stacks use
disjoint knobs (`db_name` exists only for RDS, the IP allowlist only for
EKS). A flat shared file would make every run emit a dozen "Value for
undeclared variable" warnings for the other stacks' keys; storing
everything as keys of one declared `config` object keeps runs silent and
gives every knob typed `optional()` defaults (see any environment's
`variables.tf`).

Conventions:

- Only genuinely variable knobs belong here (region, IPs, sizing); anything
  needing interpolation stays in code.
- `cluster_endpoint_public_access_cidrs` is **required** — eks apply fails
  until you set your current IP. Update it whenever your ISP rotates it,
  then re-apply eks.
- `bootstrap/` stays outside this scheme (local state, literal backend).

#### Updating your IP: `scripts/allow-my-ip.sh`

When your public IP changes you get locked out of `kubectl` until the
allow-list is updated. The helper script automates the recovery:

```bash
./scripts/allow-my-ip.sh                # detect IP + apply the cluster change
./scripts/allow-my-ip.sh --dry-run      # just show what would change
./scripts/allow-my-ip.sh --full-apply   # cluster change, then full terraform apply
./scripts/allow-my-ip.sh --cidr 1.2.3.4 # override the detected IP (e.g. VPN)
```

How it stays reliable even mid-lockout: it updates
`cluster_endpoint_public_access_cidrs` in `shared.tfvars` and applies **only**
the cluster resource first (`terraform apply -target=module.eks.aws_eks_cluster.this`),
which talks to the AWS EKS *service* API rather than the cluster API — so it
works regardless of whether `kubectl` can currently reach the cluster. It then
runs `terraform plan` (to surface any other drift), refreshes kubeconfig, and
verifies `kubectl get nodes`.

### Changing the DB secret

The catalog database credentials come from Secrets Manager
(`config.secret_id`, default `retail-store/catalog/db2`). To point the
stack at a different secret:

1. Create the new secret with **exact** JSON keys
   `RETAIL_CATALOG_PERSISTENCE_USER` and `RETAIL_CATALOG_PERSISTENCE_PASSWORD`.
2. Set `secret_id` in `environments/shared.tfvars` (edit the symlinked file).
3. Update `secretName` in `k8s/charts/catalog/values.yaml` to match — the
   chart cannot read Terraform variables.
4. Apply in order: `terraform apply` in eks (updates the Pod Identity role's
   policy ARN), then rds.
5. Re-publish/upgrade: `helm upgrade` catalog in each namespace.

> ⚠️ If the new secret contains a **different username**, changing it forces
> RDS to replace the DB instance (data loss). Same username + new password
> applies in place.

The backends reference the bucket name defined in `bootstrap/variables.tf`
(`retail-store-dev-terraform-state`) — backend blocks cannot use variables,
so that literal must stay in sync manually; every other reference reads it
from `config.state_bucket`.

The `environments/eks` config reads the VPC from `environments/network` via
`terraform_remote_state`; the VPC subnets carry the required
`kubernetes.io/cluster/retail-store` tags (see the `cluster_name` variable).

## Naming

The account hosts a single environment, so resources have no dev/prod prefix.
The EKS cluster (and VPC) are named `retail-store`, ECR repositories are named
directly after the microservices (`ui`, `catalog`, `cart`, `checkout`, `orders`),
and VPC subnets are `public-N` / `private-N`.

## Observability — ADOT add-on, AWS X-Ray, CloudWatch Logs, and AMP

The `eks` environment installs the observability pieces alongside the
cluster:

1. The **`adot` EKS add-on** (the ADOT Operator), versioned by
   `config.adot_addon_version` (default the latest EKS build for the region).
   The Operator watches `OpenTelemetryCollector` custom resources and deploys
   the ADOT collector.
2. An **IAM role `eks-adot-collector`** with the managed
   `AWSXRayDaemonWriteAccess` and `CloudWatchAgentServerPolicy` policies plus an
   inline `aps:RemoteWrite` grant, so the collector can write traces to X-Ray,
   logs to CloudWatch Logs, and metrics to AMP.
3. An **EKS Pod Identity association** binding that role to the
   `aws-otel-collector` service account in the `aws-otel-eks` namespace.
4. An **AWS Managed Prometheus workspace** (`retail-store`) used as the metrics
   store. The workspace ID / query endpoint / remote-write URL are surfaced as
   outputs (`amp_workspace_id`, `amp_workspace_endpoint`, `amp_remote_write_url`).

The collector CR, RBAC, and ClusterIP service are plain manifests in
[`k8s/observability/`](../k8s/observability/) — see `k8s/README.md →
Observability` for the deploy steps and the cost-control config (filter +
tail-sampling for traces, namespace filter + 7-day retention for logs, tight
scrape scope + 30s interval + sample limits for metrics).

## Notes

- The AWS account is **free-tier restricted**: node groups must use a
  free-tier-eligible instance type (`t3.micro`), otherwise instance launch fails.
- Cluster access is granted to the current IAM principal via an explicit
  `AmazonEKSClusterAdminPolicy` access entry (`kubectl` works out of the box).
