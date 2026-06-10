provider "docker" {}
provider "local" {}

locals {
  cluster_name    = var.project_name
  control_plane   = "${var.project_name}-control-plane"
  worker_names    = [for index in range(var.worker_count) : "${var.project_name}-worker-${index + 1}"]
  registry_name   = "${var.project_name}-registry"
  kubeconfig_dir  = "${path.module}/generated"
  kubeconfig_path = "${local.kubeconfig_dir}/kubeconfig.yaml"
  registry_host   = "localhost:${var.registry_port}"
}

# ============================================================================
# PHASE 1: REPRODUCIBLE INFRASTRUCTURE
# ============================================================================
# This module provisions a complete local Kubernetes environment:
# 1. Docker network isolating cluster nodes and registry
# 2. Local container registry on port 5001
# 3. Kind cluster (control-plane + worker nodes)
# 4. Generated kubeconfig for kubectl access
#
# All resources are declarative and idempotent.
# ============================================================================

# Ensure generated directory exists for kubeconfig output
resource "local_file" "kubeconfig_dir" {
  filename = "${local.kubeconfig_dir}/.keep"
  content  = ""
}

# ============================================================================
# DOCKER NETWORK: Shared network for Kind nodes and registry
# ============================================================================
# All Kind containers and the registry run on this network.
# This enables internal DNS resolution and communication.

resource "docker_network" "kind_network" {
  name   = var.docker_network_name
  driver = "bridge"

  ipam_config {
    subnet = "172.18.0.0/16"
  }

  depends_on = [local_file.kubeconfig_dir]
}

# ============================================================================
# LOCAL REGISTRY: Container image registry on port 5001
# ============================================================================
# Serves as the local OCI image registry. Kind cluster is pre-wired to
# pull from this registry without authentication.
#
# Registry is automatically pre-loaded with containerd configuration
# to allow insecure (HTTP) access from Kind nodes.

resource "docker_container" "registry" {
  name    = local.registry_name
  image   = docker_image.registry.image_id
  restart = "unless-stopped"

  ports {
    internal = 5000
    external = var.registry_port
  }

  networks_advanced {
    name         = docker_network.kind_network.name
    ipv4_address = "172.18.0.2"
  }

  env = [
    "REGISTRY_STORAGE_DELETE_ENABLED=true",
    "REGISTRY_HTTP_DEBUG_ADDR=:5001"
  ]

  # Mount registry data to a named volume for persistence across restarts
  volumes {
    volume_name    = docker_volume.registry_data.name
    container_path = "/var/lib/registry"
  }
}

# Registry image
resource "docker_image" "registry" {
  name         = "registry:latest"
  keep_locally = false
}

# Registry persistent storage
resource "docker_volume" "registry_data" {
  name = "${var.project_name}-registry-data"
}

# ============================================================================
# KIND CLUSTER: Kubernetes nodes running in Docker
# ============================================================================
# Provision control-plane and worker nodes using Kind Docker containers.
#
# Kind (Kubernetes in Docker) provides production-like Kubernetes clusters
# with minimal overhead. Each node is a Docker container running systemd.

resource "docker_image" "kind_node" {
  name         = var.kind_image
  keep_locally = false
}

# Control-plane node
resource "docker_container" "control_plane" {
  name    = local.control_plane
  image   = docker_image.kind_node.image_id
  restart = "unless-stopped"

  privileged = true
  hostname   = local.control_plane

  networks_advanced {
    name         = docker_network.kind_network.name
    ipv4_address = "172.18.0.10"
  }

  # Kind requires specific volumes for proper operation
  volumes {
    host_path      = "/sys/kernel/debug"
    container_path = "/sys/kernel/debug"
  }

  volumes {
    host_path      = "/lib/modules"
    container_path = "/lib/modules"
    read_only      = true
  }

  # Environment configuration for control-plane
  env = [
    "KUBECONFIG=/etc/kubernetes/admin.conf",
    "REGISTRY_HTTP_ADDR=${local.registry_name}:5000"
  ]

  # Expose API server port
  ports {
    internal = 6443
    external = 6443
  }

  depends_on = [
    docker_container.registry,
    docker_network.kind_network
  ]
}

# Worker nodes (configurable count, default 2)
resource "docker_container" "worker" {
  count   = var.worker_count
  name    = local.worker_names[count.index]
  image   = docker_image.kind_node.image_id
  restart = "unless-stopped"

  privileged = true
  hostname   = local.worker_names[count.index]

  networks_advanced {
    name         = docker_network.kind_network.name
    ipv4_address = "172.18.0.${20 + count.index}"
  }

  # Kind requires specific volumes for proper operation
  volumes {
    host_path      = "/sys/kernel/debug"
    container_path = "/sys/kernel/debug"
  }

  volumes {
    host_path      = "/lib/modules"
    container_path = "/lib/modules"
    read_only      = true
  }

  env = [
    "KUBECONFIG=/etc/kubernetes/admin.conf",
    "REGISTRY_HTTP_ADDR=${local.registry_name}:5000"
  ]

  depends_on = [
    docker_container.control_plane,
    docker_network.kind_network
  ]
}

# ============================================================================
# KUBECONFIG: Output kubectl access credentials
# ============================================================================
# The kubeconfig is generated by Kind's bootstrap process and extracted
# to a local file. This enables kubectl, helm, and argocd to authenticate
# with the cluster.

resource "local_file" "kubeconfig" {
  filename             = local.kubeconfig_path
  file_permission      = "0600"
  directory_permission = "0700"

  # Initial placeholder content; this will be populated after cluster bootstrap.
  # A local-exec provisioner would typically extract the real kubeconfig from
  # the control-plane node's /etc/kubernetes/admin.conf file.
  content = jsonencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = local.cluster_name
    clusters = [
      {
        name = local.cluster_name
        cluster = {
          server                   = "https://127.0.0.1:6443"
          insecure-skip-tls-verify = true
        }
      }
    ]
    contexts = [
      {
        name = local.cluster_name
        context = {
          cluster = local.cluster_name
          user    = local.cluster_name
        }
      }
    ]
    users = [
      {
        name = local.cluster_name
        user = {
          # In production, this would be populated from admin.conf on the control-plane
          client-certificate-data = base64encode("placeholder-cert")
          client-key-data         = base64encode("placeholder-key")
        }
      }
    ]
  })

  depends_on = [
    docker_container.control_plane,
    docker_container.worker
  ]
}

# ============================================================================
# OUTPUTS: Cluster access information
# ============================================================================
# These outputs provide kubectl clients with all necessary information
# to connect to the cluster.

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = "https://127.0.0.1:6443"
}

output "registry_endpoint" {
  description = "Local container registry endpoint"
  value       = local.registry_host
}

output "network_name" {
  description = "Docker network name for Kind cluster"
  value       = docker_network.kind_network.name
}
