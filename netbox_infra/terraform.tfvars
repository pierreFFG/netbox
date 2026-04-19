region             = "ca-central-1"
environment        = "Test"
private_subnet_ids = ["subnet-00cb63a504994fdca", "subnet-06278f3fd1aad4fac"]
vpc_id             = "vpc-0841e283345d9925f"

# EKS
cluster_name          = "netbox00-eks-test"
cluster_oidc_id       = "71533274C5CD8191A7DD2BE829AF5D69"
k8s_version           = "1.35"
eks_admin_role_arn    = "arn:aws:iam::629068383519:role/aws-reserved/sso.amazonaws.com/ca-central-1/AWSReservedSSO_AdministratorAccess_6e97bf1d1f25e04b"
eks_cluster_role_name = "aws99-eks-cluster-netbox-role"
eks_node_role_name    = "aws99-eks-node-netbox-role"

# Karpenter NodePool
node_pools          = ["general-purpose", "system"]
nodepool_name       = "nodepool-eks-netbox-test"
nodeclass_name      = "nodepool-eks-netbox-test"
capacity_type       = ["on-demand"]
architecture        = ["amd64"]
instance_categories = ["c", "r", "m"]

# ECR
repositories = [
  {
    name           = "netbox-image"
    tag_mutability = "MUTABLE"
    scan_on_push   = true
    force_delete   = false
  }
]

# RDS PostgreSQL (CCCS-Medium: Multi-AZ, backup 30j, gp3, >1000 devices)
rds_identifier              = "netbox00-rds-postgres-test"
rds_instance_class          = "db.t3.large"
rds_engine_version          = "15.10"
rds_allocated_storage       = 100
rds_max_allocated_storage   = 200
rds_storage_type            = "gp3"
rds_master_username         = "netboxadmin"
rds_db_name                 = "ORCL"
rds_backup_retention_period = 30

# Redis (CCCS-Medium: Multi-AZ, encryption, auth token)
redis_cluster_name = "netbox-redis-test"
redis_node_type    = "cache.t3.medium"

# Tags SQSS
dic                     = "4-2-1"
nom_equipe              = "CEI"
nom_etab                = "SanteQc"
nom_actif_informationel = "NETBOX"
account_id              = "629068383519"
classification          = "false"

# DNS
hosted_zone_id                = "Z03223882T7MQ3KRV58KY"
hosted_zone_type              = "private"
acm_validation_hosted_zone_id = "Z0811627115HEYTKBQUFW"
domain_zone                   = "aws.sante.quebec"
netbox_fqdn                   = "test.netbox.aws.sante.quebec"
dns_validation_aws_profile    = "Network"
ingress_class_name            = "eks-auto-alb"
scheme                        = "internal"

# NetBox App
netbox_image_tag     = "v4.1.4"
netbox_replicas      = 2
netbox_namespace     = "netbox"
alb_logs_bucket_name = "aws-accelerator-elb-access-logs-324037318411-ca-central-1"
alb_logs_prefix      = "alb-logs/netbox00-test"

# Déploiement en deux phases
# Phase 1 (false) : EKS, RDS, Redis, S3, KMS, ECR, Certificats, CCCS, Secrets Manager
# Phase 2 (true)  : Addons EKS, Pod Identity, Deployments K8s, ConfigMap, Ingress
deploy_phase_2 = true
