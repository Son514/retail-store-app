# ------------------------------------------------------------------
# Helm provider (used by helm_release resources below)
# ------------------------------------------------------------------

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name]
    }
  }
}

# ------------------------------------------------------------------
# IAM
# ------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = "eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role" "node" {
  name = "eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# ------------------------------------------------------------------
# Cluster
# ------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name                          = var.cluster_name
  role_arn                      = aws_iam_role.cluster.arn
  version                       = var.cluster_version
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_public_access  = var.cluster_endpoint_public_access
    endpoint_private_access = var.cluster_endpoint_private_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Attach the admin cluster access policy to the cluster creator so kubectl
# works. The access entry itself is auto-created by EKS via
# bootstrap_cluster_creator_admin_permissions and is NOT managed here
# (an explicit entry resource conflicts with the bootstrapped one).
resource "aws_eks_access_policy_association" "creator_admin" {
  cluster_name  = aws_eks_cluster.this.name
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_caller_identity.current.arn

  access_scope {
    type = "cluster"
  }

  depends_on = [time_sleep.cluster_wait]
}

# ------------------------------------------------------------------
# Managed addons (required when bootstrap_self_managed_addons = false)
# ------------------------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_eks_addon" "secrets_store_csi_provider" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-secrets-store-csi-driver-provider"
  resolve_conflicts_on_create = "OVERWRITE"
}

# Required by the ADOT add-on below: the OpenTelemetry Operator it installs
# needs cert-manager for its validating/mutating webhooks and serving certs.
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.1"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }

  depends_on = [
    aws_eks_node_group.this,
    # Install after the AWS Load Balancer Controller so its mutating webhook
    # (mservice.elbv2.k8s.aws) is ready; otherwise cert-manager's Service is
    # rejected with "no endpoints available" during concurrent bring-up.
    helm_release.aws_lb_controller,
  ]
}

# ADOT (AWS Distro for OpenTelemetry) operator. Must be installed after
# cert-manager, otherwise add-on creation fails with K8sResourceNotFound.
resource "aws_eks_addon" "adot" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "adot"
  addon_version               = var.adot_addon_version
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [
    helm_release.cert_manager,
  ]
}

# ------------------------------------------------------------------
# Observability — ADOT collector IAM (writes traces to AWS X-Ray and
# logs to CloudWatch Logs)
# ------------------------------------------------------------------

resource "aws_iam_role" "adot_collector" {
  name = "eks-adot-collector"

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

resource "aws_iam_role_policy_attachment" "adot_collector" {
  role       = aws_iam_role.adot_collector.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "adot_collector_logs" {
  role       = aws_iam_role.adot_collector.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# AMP (Amazon Managed Prometheus) workspace the collector remotely-writes
# metrics to, and the aps:RemoteWrite grant on the collector's Pod Identity
# role (the sigv4auth extension signs the request with this role).
# Note: AMP data retention is fixed by AWS at 150 days (not configurable).
resource "aws_prometheus_workspace" "amp" {
  alias = "retail-store"

  tags = var.tags
}

resource "aws_iam_role_policy" "adot_collector_amp" {
  name = "amp-remote-write"
  role = aws_iam_role.adot_collector.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:RemoteWrite"]
      Resource = aws_prometheus_workspace.amp.arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "adot_collector" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "aws-otel-eks"
  service_account = "aws-otel-collector"
  role_arn        = aws_iam_role.adot_collector.arn
}

# ------------------------------------------------------------------
# Pod Identity — IAM role for test pod S3 access
# ------------------------------------------------------------------

resource "aws_iam_role" "test_pod_s3" {
  name = "eks-test-pod-s3"

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

resource "aws_iam_role_policy_attachment" "test_pod_s3" {
  role       = aws_iam_role.test_pod_s3.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_eks_pod_identity_association" "test_pod_s3" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "development"
  service_account = "test-pod-sa"
  role_arn        = aws_iam_role.test_pod_s3.arn
}

# ------------------------------------------------------------------
# AWS Secrets Manager — catalog database credentials (created externally)
# ------------------------------------------------------------------

data "aws_secretsmanager_secret" "catalog_db" {
  name = var.secret_id
}

# ------------------------------------------------------------------
# Pod Identity — IAM role for catalog secret access
# ------------------------------------------------------------------

resource "aws_iam_role" "catalog_secret" {
  name = "eks-catalog-secret"

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

resource "aws_iam_role_policy" "catalog_secret" {
  name = "secrets-manager-access"
  role = aws_iam_role.catalog_secret.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = data.aws_secretsmanager_secret.catalog_db.arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "catalog_secret" {
  for_each = toset(var.app_namespaces)

  cluster_name    = aws_eks_cluster.this.name
  namespace       = each.value
  service_account = "catalog-sa"
  role_arn        = aws_iam_role.catalog_secret.arn
}

# ------------------------------------------------------------------
# AWS Load Balancer Controller — IAM + Helm
# ------------------------------------------------------------------

resource "aws_iam_role" "aws_lb_controller" {
  name = "eks-aws-lb-controller"

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

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
}

resource "aws_iam_policy" "aws_lb_controller" {
  name        = "eks-aws-lb-controller"
  description = "IAM policy for the AWS Load Balancer Controller"
  policy      = file("${path.module}/iam-policy-aws-lb-controller.json")
}

resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_lb_controller.arn
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.13.3"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.this.name
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_lb_controller.arn
  }

  depends_on = [
    aws_eks_node_group.this,
    aws_eks_pod_identity_association.aws_lb_controller,
  ]
}

# ------------------------------------------------------------------
# metrics-server — supplies resource metrics for HorizontalPodAutoscaler
# ------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  namespace  = "kube-system"

  depends_on = [
    aws_eks_node_group.this,
  ]
}

# ------------------------------------------------------------------
# Node security group
# ------------------------------------------------------------------

resource "aws_security_group" "node" {
  name        = "eks-node"
  description = "Security group for the EKS managed node group"
  vpc_id      = var.vpc_id

  tags = var.tags
}

resource "aws_security_group_rule" "node_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "node_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "node_ingress_cluster" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_security_group.node.id
}

resource "aws_security_group_rule" "node_ingress_dns_udp" {
  type              = "ingress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "node_ingress_dns_tcp" {
  type              = "ingress"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.node.id
}

# Allow nodes to reach the cluster API on the EKS-managed cluster SG.
resource "aws_security_group_rule" "cluster_ingress_node" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.node.id
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# ------------------------------------------------------------------
# Node group
# ------------------------------------------------------------------

resource "time_sleep" "cluster_wait" {
  create_duration = "90s"

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "managed"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_group_instance_types
  ami_type        = "AL2023_x86_64_STANDARD"
  version         = var.cluster_version

  scaling_config {
    desired_size = var.node_group_desired_size
    min_size     = var.node_group_min_size
    max_size     = var.node_group_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
    aws_eks_addon.vpc_cni,
    time_sleep.cluster_wait,
  ]
}

resource "time_sleep" "node_group_wait" {
  create_duration = "60s"

  depends_on = [aws_eks_node_group.this]
}
