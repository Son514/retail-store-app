output "karpenter_namespace" {
  description = "Namespace where Karpenter is installed"
  value       = "kube-system"
}

output "nodepool_name" {
  description = "Name of the Karpenter NodePool"
  value       = "spot"
}
