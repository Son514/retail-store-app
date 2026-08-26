# ------------------------------------------------------------------
# Kubernetes provider (used by kubernetes_manifest resources)
# ------------------------------------------------------------------

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

provider "kubectl" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

# ------------------------------------------------------------------
# Karpenter — IAM (controller + node instance profile)
# ------------------------------------------------------------------

resource "aws_iam_role" "karpenter_controller" {
  name = "eks-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-controller"
  role = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeProducts",
          "ec2:DescribeLaunchTemplateVersions",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
        ]
        Resource = [
          aws_iam_role.karpenter_controller.arn,
          var.node_iam_role_arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "spot.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
        ]
        Resource = "arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
        Resource = aws_sqs_queue.karpenter.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.region}::parameter/aws/service/eks/optimized-ami/*"
      },
    ]
  })
}

# ------------------------------------------------------------------
# Interruption queue ( spot / capacity rebalance notifications)
# ------------------------------------------------------------------

resource "aws_sqs_queue" "karpenter" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300

  tags = var.tags
}

# ------------------------------------------------------------------
# Pod Identity — controller → IAM role
# ------------------------------------------------------------------

resource "aws_eks_pod_identity_association" "karpenter_controller" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_controller.arn
}

# ------------------------------------------------------------------
# Helm — Karpenter controller
# ------------------------------------------------------------------

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.3.1"
  namespace  = "kube-system"

  values = [
    yamlencode({
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
        interruptionQueue = aws_sqs_queue.karpenter.name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
        }
      }
      tolerations = [
        {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }
    })
  ]

  depends_on = [
    aws_eks_pod_identity_association.karpenter_controller,
  ]
}

# ------------------------------------------------------------------
# CRDs — EC2NodeClass + NodePool
# ------------------------------------------------------------------

resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = <<-EOF
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: ${element(split("/", var.node_iam_role_arn), 1)}
      amiSelectorTerms:
        - alias: al2023@latest
      subnetSelectorTerms:
        %{for id in var.private_subnet_ids}
        - id: ${id}
        %{endfor}
      securityGroupSelectorTerms:
        - id: ${var.node_security_group_id}
      tags:
        %{for key, value in var.tags}
        ${key}: "${value}"
        %{endfor}
  EOF

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "nodepool" {
  yaml_body = <<-EOF
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: spot
    spec:
      template:
        spec:
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values:
                - spot
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - t3.micro
                - t3.small
            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - ap-southeast-1a
                - ap-southeast-1b
                - ap-southeast-1c
            - key: kubernetes.io/arch
              operator: In
              values:
                - amd64
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
      limits:
        cpu: "16"
        memory: 24Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 60s
  EOF

  depends_on = [kubectl_manifest.ec2nodeclass]
}

# ------------------------------------------------------------------
# Data sources
# ------------------------------------------------------------------

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
