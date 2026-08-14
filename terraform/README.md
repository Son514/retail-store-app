# Terraform — AWS infrastructure

Modular Terraform for the retail-store-app AWS infrastructure (region `ap-southeast-1`).

## Layout

| Path                         | Purpose                                                                  |
| ---------------------------- | ------------------------------------------------------------------------ |
| `bootstrap/`                 | Creates the S3 bucket that stores remote state. State is local.           |
| `environments/network/`      | VPC stack (subnets, IGW, NAT, route tables); remote state in the bucket.  |
| `environments/eks/`          | EKS cluster + managed node group, using the network's private subnets.    |
| `environments/ecr/`          | ECR repositories for the microservices; remote state in the bucket.       |
| `modules/vpc/`               | Reusable VPC module.                                                      |
| `modules/eks/`               | Reusable hand-written EKS module (IAM, cluster, SG, node group, OIDC).    |
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

# 3. EKS: cluster + node group (takes ~10-15 min)
cd ../environments/eks
terraform init && terraform plan && terraform apply

# 4. ECR: microservice repositories (no cluster needed)
cd ../environments/ecr
terraform init && terraform plan && terraform apply
```

The backends reference the bucket name defined in `bootstrap/variables.tf`
(`retail-store-dev-terraform-state`); keep them in sync.

The `environments/eks` config reads the VPC from `environments/network` via
`terraform_remote_state`; the VPC subnets carry the required
`kubernetes.io/cluster/retail-store` tags (see the `cluster_name` variable).

## Naming

The account hosts a single environment, so resources have no dev/prod prefix.
The EKS cluster (and VPC) are named `retail-store`, ECR repositories are named
directly after the microservices (`ui`, `catalog`, `cart`, `checkout`, `orders`),
and VPC subnets are `public-N` / `private-N`.

## Notes

- The AWS account is **free-tier restricted**: node groups must use a
  free-tier-eligible instance type (`t3.micro`), otherwise instance launch fails.
- Cluster access is granted to the current IAM principal via an explicit
  `AmazonEKSClusterAdminPolicy` access entry (`kubectl` works out of the box).
