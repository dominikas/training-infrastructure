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
      version = "= 2.5.1"
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

data "aws_eks_cluster" "msur"{
  name = module.aws-eks.eks_cluster_id
}

# Network configuration
module "aws-network" {
  source                = "github.com/dominikas/infrastructure-training/module-aws-network"
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
module "aws-eks" {
  source             = "github.com/dominikas/infrastructure-training/module-aws-kubernetes"
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
  nodegroup_max_size       = 2
}

# GitOps Config
module "argo-cd-server" {
  source = "github.com/dominikas/infrastructure-training/module-argo-cd"
  kubernetes_cluster_id = module.aws-eks.eks_cluster_id
  kubernetes_cluster_name = module.aws-eks.eks_cluster_name
  kubernetes_cluster_cert_data = module.aws-eks.eks_cluster_certificate_data
  kubernetes_cluster_endpoint = module.aws-eks.eks_cluster_endpoint
  eks_nodegroup_id = module.aws-eks.eks_cluster_nodegroup_id
}