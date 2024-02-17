terraform {
  backend "s3" {
    bucket = "domi-devops-terraform-state"
    key    = "terraform/backend"
    region = "eu-west-1"
  }

  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.16.1"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "= 2.12.1"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.33"
    }
  }
}

variable "postgres_password" {
  type = string
}

locals {
  env_name         = "sandbox"
  k8s_cluster_name = "ms-cluster"
  aws_region       = "eu-west-1"
}

provider "aws" {
  region = local.aws_region
}

data "aws_eks_cluster" "msur" {
  name = module.aws-kubernetes-cluster.eks_cluster_id
}

# Network configuration
module "aws-network" {
  source                = "../module-aws-network"
  env_name              = local.env_name
  vpc_name              = "msur-VPC"
  cluster_name          = local.k8s_cluster_name
  aws_region            = local.aws_region
  main_vpc_cidr         = "10.10.0.0/16"
  public_subnet_a_cidr  = "10.10.0.0/18"
  public_subnet_b_cidr  = "10.10.64.0/18"
  private_subnet_a_cidr = "10.10.128.0/18"
  private_subnet_b_cidr = "10.10.192.0/18"
}

# EKS Config
module "aws-kubernetes-cluster" {
  source             = "../module-aws-kubernetes"

  ms_namespace       = "microservices"
  env_name           = local.env_name
  aws_region         = local.aws_region
  cluster_name       = local.k8s_cluster_name
  vpc_id             = module.aws-network.vpc_id
  cluster_subnet_ids = module.aws-network.subnet_ids

  nodegroup_subnet_ids     = module.aws-network.private_subnet_ids
  nodegroup_disk_size      = "20"
  nodegroup_instance_types = ["t3.medium"]
  nodegroup_desired_size   = 1
  nodegroup_min_size       = 1
  nodegroup_max_size       = 5
}

provider "kubernetes" {
  load_config_file       = false
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.msur.certificate_authority.0.data)
  host                   = data.aws_eks_cluster.msur.endpoint
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", "${data.aws_eks_cluster.msur.name}"]
  }
}

# GitOps Config
module "argo-cd-server" {
  source                       = "../module-argo-cd"
  kubernetes_cluster_id        = module.aws-kubernetes-cluster.eks_cluster_id
  kubernetes_cluster_name      = module.aws-kubernetes-cluster.eks_cluster_name
  kubernetes_cluster_cert_data = module.aws-kubernetes-cluster.eks_cluster_certificate_data
  kubernetes_cluster_endpoint  = module.aws-kubernetes-cluster.eks_cluster_endpoint
  eks_nodegroup_id             = module.aws-kubernetes-cluster.eks_cluster_nodegroup_id
}

#Database config
module "aws-databases" {
  source = "../module-aws-db"

  aws_region     = local.aws_region
  postgres_password = var.postgres_password
  vpc_id         = module.aws-network.vpc_id
  eks_id         = data.aws_eks_cluster.msur.id
  eks_sg_id      = module.aws-kubernetes-cluster.eks_cluster_security_group_id
  subnet_a_id    = module.aws-network.private_subnet_ids[0]
  subnet_b_id    = module.aws-network.private_subnet_ids[1]
  env_name       = local.env_name
  route53_id     = module.aws-network.route53_id
}

#Traefik config
module "traefik" {
  source = "../module-aws-traefik"

  aws_region                   = local.env_name
  kubernetes_cluster_id        = data.aws_eks_cluster.msur.id
  kubernetes_cluster_name      = module.aws-kubernetes-cluster.eks_cluster_name
  kubernetes_cluster_cert_data = module.aws-kubernetes-cluster.eks_cluster_certificate_data
  kubernetes_cluster_endpoint  = module.aws-kubernetes-cluster.eks_cluster_endpoint

  eks_nodegroup_id = module.aws-kubernetes-cluster.eks_cluster_nodegroup_id
}