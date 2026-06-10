output "cluster_name" {
  description = "Logical name of the local Kind cluster."
  value       = local.cluster_name
}

output "kubeconfig_path" {
  description = "Location where the generated kubeconfig will be written."
  value       = local.kubeconfig_path
}

output "registry_port" {
  description = "Host port exposed by the local registry."
  value       = var.registry_port
}
