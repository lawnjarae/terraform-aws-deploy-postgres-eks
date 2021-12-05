terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.20.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.1"
    }
  }
}

data "terraform_remote_state" "eks" {
  backend = "local"

  config = {
    path = "../provision-eks-cluster/terraform.tfstate"
  }
}

# Retrieve EKS cluster information
provider "aws" {
  region = data.terraform_remote_state.eks.outputs.region
}

data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      data.aws_eks_cluster.cluster.name
    ]
  }
}

resource "kubernetes_deployment" "postgres" {
  metadata {
    name = "postgres"
    labels = {
      App = "Postgres"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        App = "Postgres"
      }
    }
    template {
      metadata {
        labels = {
          App = "Postgres"
        }
      }
      spec {
        container {
          image = "postgres:14.1"
          name  = "db-dev"

          env {
            name  = "POSTGRES_PASSWORD"
            value = "TestPassword111!!!"
          }

          env {
            name  = "POSTGRES_USEAR"
            value = "postgres"
          }

          port {
            container_port = 8080
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name = "postgres"
  }
  spec {
    selector = {
      App = kubernetes_deployment.postgres.spec.0.template.0.metadata[0].labels.App
    }
    port {
      port        = 5432
      target_port = 5432
    }

    type = "LoadBalancer"
  }
}

output "lb_ip" {
  value = kubernetes_service.postgres.status.0.load_balancer.0.ingress.0.hostname
}
