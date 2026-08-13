# Terraform — Network infrastructure

Modular Terraform for the retail-store-app AWS infrastructure (region `ap-southeast-1`).

## Layout

| Path                         | Purpose                                                        |
| ---------------------------- | -------------------------------------------------------------- |
| `bootstrap/`                 | Creates the S3 bucket that stores remote state. State is local.|
| `environments/network/`      | VPC stack; remote state in the bootstrap bucket.               |
| `modules/vpc/`               | Reusable VPC module (VPC, subnets, IGW, NAT, route tables).    |

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
```

The `network` backend references the bucket name defined in `bootstrap/variables.tf`
(`retail-store-dev-terraform-state`); keep them in sync.
