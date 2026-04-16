# =============================================================================
# ECR - Registre d'images Docker
# =============================================================================

module "ecr" {
  source                 = "git::https://RSSS-CEI-C@dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//ecr?ref=master"
  repositories           = var.repositories
  dockerhub_pat_username = "gouvernancecei"
  dockerhub_pat_password = "dckr_pat_NpOVlIltdtKca22zO8URPW3S4xg"
}

# =============================================================================
# KMS - Clé de chiffrement
# =============================================================================

module "keyForNetbox" {
  source = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//kms?ref=master"
  alias  = "keyForNetbox"
}

# =============================================================================
# EKS - Cluster Kubernetes
# =============================================================================

module "eks" {
  source                = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//eks?ref=master"
  k8s_version           = var.k8s_version
  environment           = var.environment
  cluster_name          = var.cluster_name
  private_subnet_ids    = var.private_subnet_ids
  eks_admin_role_arn    = var.eks_admin_role_arn
  node_pools            = var.node_pools
  eks_cluster_role_name = var.eks_cluster_role_name
  eks_node_role_name    = var.eks_node_role_name
}

# =============================================================================
# EKS Node - Configuration des nœuds Karpenter
# =============================================================================

module "eks_node" {
  source                  = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//eks_node?ref=master"
  cluster_name            = var.cluster_name
  private_subnet_ids      = var.private_subnet_ids
  vpc_id                  = var.vpc_id
  nodepool_name           = var.nodepool_name
  nodeclass_name          = var.nodeclass_name
  capacity_type           = var.capacity_type
  architecture            = var.architecture
  instance_categories     = var.instance_categories
  eks_node_role_name      = var.eks_node_role_name
  region                  = var.region
  dic                     = var.dic
  nom_equipe              = var.nom_equipe
  nom_etab                = var.nom_etab
  nom_actif_informationel = var.nom_actif_informationel
  account_id              = var.account_id
  classification          = var.classification

  depends_on = [module.eks]
}

# =============================================================================
# EKS Config - Pod Identity pour NetBox
# =============================================================================

module "eks_config" {
  source              = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//eks_config?ref=master"
  for_each            = var.deploy_phase_2 ? local.pod_identities : {}
  account_id          = local.account_id
  cluster_name        = var.cluster_name
  app_name            = each.value.app_name
  pod_namespace       = each.value.pod_namespace
  pod_service_account = "${each.value.app_name}-sa"

  pod_permissions_policy = each.value.pod_permissions_policy
  managed_policy_arns    = each.value.managed_policies
  depends_on             = [module.eks]
}

# =============================================================================
# RDS PostgreSQL - Base de données NetBox
# =============================================================================

module "rds" {
  source                                = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//rds?ref=master"
  vpc_id                                = var.vpc_id
  account_id                            = local.account_id
  rds_role_name                         = "netbox00-rds-role-test"
  private_subnet_ids                    = var.private_subnet_ids
  db_subnet_group_name                  = "netbox00-rds-subnetgroup-test"
  db_identifier                         = var.rds_identifier
  db_engine_type                        = "postgres"
  db_instance_class                     = var.rds_instance_class
  db_engine_version                     = var.rds_engine_version
  db_allocated_storage                  = var.rds_allocated_storage
  backup_retention_period               = var.rds_backup_retention_period
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  license_model                         = "postgresql-license"

  ingress_rules = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = "10.0.0.0/8"
      description = "Allow PostgreSQL access from internal network"
    },
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      source_security_group_id = module.eks.id_groupe_securite_control_plane
      description              = "Allow PostgreSQL access from EKS cluster"
    }
  ]
}

# =============================================================================
# Redis - Cache et sessions NetBox
# =============================================================================

module "redis_netbox" {
  source             = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//redis?ref=master"
  account_id         = local.account_id
  private_subnet_ids = var.private_subnet_ids
  vpc_id             = var.vpc_id
  redis_cluster_name = var.redis_cluster_name
  node_type          = var.redis_node_type
  multi_az_enabled   = true
  redis_engine_version   = "7.0"
  maxmemory_policy       = "allkeys-lru"
  maintenance_window     = "sun:02:00-sun:03:00"
  snapshot_window        = "03:00-04:00"
  snapshot_retention_limit = 7

  redis_ingress_rules = [
    {
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      source_security_group_id = module.eks.id_groupe_securite_control_plane
      description              = "Allow Redis access from EKS pods"
    }
  ]

  depends_on = [module.eks]
}

# =============================================================================
# S3 - Stockage des médias NetBox
# =============================================================================

module "s3_netbox_media" {
  source                  = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//s3?ref=master"
  account_id              = local.account_id
  identifiant             = "netbox00-media-${var.palier}"
  cle_chiffrement_externe = true
  arn_cle_chiffrement     = module.keyForNetbox.key_arn
  activer_versionnage     = true
  activer_verrouillage_objets = false
}

# =============================================================================
# Certificats ACM
# =============================================================================

locals {
  sqss_certificates = {
    netbox = {
      domain_name = "netbox.${var.palier}.${local.domain_zone}"
      env_name    = var.palier
    }
  }
}

module "certificat_netbox" {
  source            = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//certificats?ref=master"
  aws_region        = data.aws_region.current.name
  domain_zone       = local.domain_zone
  sqss_certificates = local.sqss_certificates
}
