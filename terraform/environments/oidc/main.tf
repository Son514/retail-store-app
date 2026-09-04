# ------------------------------------------------------------------
# GitHub Actions OIDC — identity provider and deploy role
#
# Lets GitHub Actions workflows assume an IAM role with short-lived
# credentials (no static access keys) to push images to ECR (and, later,
# deploy to EKS). The trust policy is scoped to a single repository.
# ------------------------------------------------------------------

locals {
  # Repository holding the actions using this role, in the
  # "<owner>/<repo>" format used by GitHub's OIDC subject claim.
  github_repo = "Son514/retail-store-app"

  # Repositories the role may push images to (private ECR, ap-southeast-1).
  ecr_repos = ["catalog", "ui"]
}

# ------------------------------------------------------------------
# IAM OIDC identity provider for GitHub
# ------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's current root CA fingerprint (openssl s_client ... -fingerprint).
  thumbprint_list = ["227203b5317f3818cab5b5ce596132bf36748c0e"]

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.config.tags)
}

# ------------------------------------------------------------------
# Deploy role (assumed by GitHub Actions)
# ------------------------------------------------------------------

resource "aws_iam_role" "github_actions_deploy" {
  name = "github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = merge({
    "created-by" = "retail-store-app"
  }, var.config.tags)
}

# ------------------------------------------------------------------
# ECR push policy (GetAuthorizationToken + image actions on the repos)
# ------------------------------------------------------------------

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid    = "GetAuthorizationToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "PushImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      for repo in local.ecr_repos :
      "arn:${data.aws_partition.current.partition}:ecr:${var.config.region}:${data.aws_caller_identity.current.account_id}:repository/${repo}"
    ]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
