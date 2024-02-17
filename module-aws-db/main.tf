provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "microservice-cluster" {
  name = "${var.eks_id}"
}

resource "aws_db_subnet_group" "rds-subnet-group" {
  name       = "${var.env_name}-rds-subnet-group"
  subnet_ids = ["${var.subnet_a_id}", "${var.subnet_b_id}"]
}

resource "aws_security_group" "db-security-group" {
  name        = "${var.env_name}-allow-eks-db"
  description = "Allow traffic from EKS managed worklods"
  vpc_id      = var.vpc_id

  ingress {
    description = "All traffic from managed EKS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
}

data "aws_security_group" "default" {
  vpc_id = var.vpc_id
  name   = "default"
}

resource "aws_db_instance" "postgres-db" {
  allocated_storage = 20
  storage_type      = "gp2"
  engine            = "postgres"
  engine_version    = "14"
  instance_class    = "db.t2.micro"
  db_name           = var.postgres_database
  identifier        = "microservices-mysql"

  username             = var.postgres_user
  password             = var.postgres_password
  parameter_group_name = "default.postgres.14"

  skip_final_snapshot = true

  db_subnet_group_name   = aws_db_subnet_group.rds-subnet-group.name
  vpc_security_group_ids = [var.eks_sg_id]
}

resource "aws_elasticache_subnet_group" "redis-subnet-group" {
  name       = "${var.env_name}-elasticache-subnet-group"
  subnet_ids = ["${var.subnet_a_id}", "${var.subnet_b_id}"]
}

resource "aws_elasticache_cluster" "redis-db" {
  cluster_id           = "microservices-redis"
  engine               = "redis"
  node_type            = "cache.m4.large"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  engine_version       = "3.2.10"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis-subnet-group.name
  security_group_ids = [aws_security_group.db-security-group.id]
}

data "aws_route53_zone" "private-zone" {
  zone_id      = var.route53_id
  private_zone = true
}

resource "aws_route53_record" "rds-instance" {
  name    = "rds.${data.aws_route53_zone.private-zone.name}"
  type    = "CNAME"
  ttl     = "300"
  zone_id = var.route53_id
  records = [aws_db_instance.postgres-db.address]
}