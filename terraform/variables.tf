variable "project_name" {
  description = "Prefix used for every Terraform-managed resource."
  type        = string
  default     = "ai-llmops-platform"
}

variable "kind_image" {
  description = "Kind node image used for the local Kubernetes cluster."
  type        = string
  default     = "kindest/node:v1.30.0"
}

variable "registry_port" {
  description = "Host port exposed by the local container registry."
  type        = number
  default     = 5001
}

variable "worker_count" {
  description = "Number of worker nodes to provision alongside the control plane."
  type        = number
  default     = 2
}

variable "docker_network_name" {
  description = "Docker network shared by the Kind nodes and local registry."
  type        = string
  default     = "ai-llmops-kind"
}
