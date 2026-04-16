region             = "ca-central-1"
environment        = "Test"
private_subnet_ids = ["subnet-XXXXXXXXXXXXXXXXX", "subnet-XXXXXXXXXXXXXXXXX"] # À remplacer avec les subnets du compte TestNetbox
vpc_id             = "vpc-XXXXXXXXXXXXXXXXX"                                   # À remplacer avec le VPC du compte TestNetbox

# EKS
cluster_name          = "netbox00-eks-test"
cluster_oidc_id       = "" # Renseigné en phase 2 après création du cluster
k8s_version           = "1.35"
eks_admin_role_arn    = "arn:aws:iam::XXXXXXXXXXXX:role/aws-reserved/sso.amazonaws.com/ca-central-1/AWSReservedSSO_SystemAdministrator_XXXXXXXXXXXXXXXX" # À remplacer
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
rds_backup_retention_period = 30

# Redis (CCCS-Medium: Multi-AZ, encryption, auth token)
redis_cluster_name = "netbox-redis-test"
redis_node_type    = "cache.t3.medium"

# Tags SQSS
dic                     = "4-2-1"
nom_equipe              = "CEI"
nom_etab                = "SanteQc"
nom_actif_informationel = "NETBOX"
account_id              = "XXXXXXXXXXXX" # À remplacer avec le compte TestNetbox
classification          = "false"

# DNS
hosted_zone_id   = "XXXXXXXXXXXXXXXXXXXXXX" # À remplacer
hosted_zone_type = "private"
domain_zone      = "netbox00.aws.sante.quebec"

# NetBox App
netbox_image_tag = "v4.1.4"
netbox_replicas  = 2
netbox_namespace = "netbox"

# Déploiement en deux phases
# Phase 1 (false) : EKS, RDS, Redis, S3, KMS, ECR, Certificats, CCCS, Secrets Manager
# Phase 2 (true)  : Addons EKS, Pod Identity, Deployments K8s, ConfigMap, Ingress
deploy_phase_2 = false
