terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "retail-store-dev-terraform-state"
    key          = "network/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.config.region
}
