variable "region" {
  description = "Region AWS de déploiement"
  type        = string
  default     = "ca-central-1"
}

variable "projet" {
  description = "Nom du projet"
  type        = string
  default     = "netbox00"
}

variable "palier" {
  description = "Palier de déploiement (dev, test, prod)"
  type        = string
  default     = "test"
}

variable "environment" {
  description = "Environment name (e.g., Dev, Test, Prod)"
  type        = string
  default     = "Test"
}

# ---- RÉSEAU ----

variable "vpc_id" {
  description = "ID du VPC LZA"
  type        = string
}

variable "private_subnet_ids" {
  description = "Liste des IDs des sous-réseaux privés"
  type        = list(string)
  default     = []
}

# ---- EKS ----

variable "cluster_name" {
  description = "Nom du cluster EKS"
  type        = string
}

variable "k8s_version" {
  description = "Version Kubernetes pour le cluster EKS"
  type        = string
  default     = "1.32"
}

variable "cluster_oidc_id" {
  description = "OIDC ID du cluster EKS (requis en phase 2 uniquement)"
  type        = string
  default     = ""
}

variable "eks_cluster_role_name" {
  description = "Nom du rôle IAM pour le cluster EKS"
  type        = string
}

variable "eks_admin_role_arn" {
  description = "ARN du rôle admin EKS"
  type        = string
}

variable "eks_node_role_name" {
  description = "Nom du rôle IAM pour les nœuds EKS"
  type        = string
  default     = "aws99-eks-netbox-node"
}

variable "node_pools" {
  description = "Liste des node pools pour le cluster EKS"
  type        = list(string)
  default     = ["general-purpose", "system"]
}

variable "nodepool_name" {
  description = "Nom du Karpenter NodePool"
  type        = string
}

variable "nodeclass_name" {
  description = "Nom du Karpenter NodeClass"
  type        = string
}

variable "capacity_type" {
  description = "Types de capacité (on-demand, spot)"
  type        = list(string)
  default     = ["on-demand"]
}

variable "instance_categories" {
  description = "Catégories d'instances EC2"
  type        = list(string)
  default     = ["c", "r", "m"]
}

variable "architecture" {
  description = "Architectures CPU"
  type        = list(string)
  default     = ["amd64"]
}

# ---- ECR ----

variable "repositories" {
  description = "Liste des dépôts ECR"
  type = list(object({
    name           = string
    tag_mutability = string
    scan_on_push   = bool
    force_delete   = bool
  }))
}

# ---- RDS PostgreSQL ----

variable "rds_identifier" {
  description = "Identifiant de l'instance RDS PostgreSQL"
  type        = string
  default     = "netbox00-rds-postgres-test"
}

variable "rds_instance_class" {
  description = "Classe d'instance RDS (CCCS: dimensionné pour >1000 devices)"
  type        = string
  default     = "db.t3.large"
}

variable "rds_engine_version" {
  description = "Version du moteur PostgreSQL"
  type        = string
  default     = "15.10"
}

variable "rds_allocated_storage" {
  description = "Stockage alloué en Go (CCCS: prévoir pour >1000 devices)"
  type        = number
  default     = 100
}

variable "rds_backup_retention_period" {
  description = "Nombre de jours de rétention des backups (CCCS minimum 30 jours)"
  type        = number
  default     = 30
}

# ---- Redis ----

variable "redis_cluster_name" {
  description = "Nom du cluster Redis"
  type        = string
  default     = "netbox-redis-test"
}

variable "redis_node_type" {
  description = "Type d'instance Redis (CCCS: dimensionné pour cache NetBox)"
  type        = string
  default     = "cache.t3.medium"
}

# ---- TAGS SQSS ----

variable "dic" {
  description = "Cote DIC pour le tagging SQSS"
  type        = string
}

variable "nom_equipe" {
  description = "Nom de l'équipe responsable"
  type        = string
}

variable "nom_etab" {
  description = "Nom de l'établissement responsable"
  type        = string
}

variable "nom_actif_informationel" {
  description = "Nom de l'actif informationnel"
  type        = string
}

variable "account_id" {
  description = "ID du compte AWS"
  type        = string
}

variable "classification" {
  description = "Classification SQSS"
  type        = string
}

# ---- DNS / CERTIFICATS ----

variable "hosted_zone_id" {
  description = "ID de la zone hébergée Route53"
  type        = string
}

variable "hosted_zone_type" {
  description = "Type de zone hébergée (private/public)"
  type        = string
  default     = "private"
}

variable "domain_zone" {
  description = "Zone DNS principale"
  type        = string
  default     = "netbox00.aws.sante.quebec"
}

# ---- NETBOX APP ----

variable "netbox_image_tag" {
  description = "Tag de l'image Docker NetBox"
  type        = string
  default     = "v4.1.4"
}

variable "netbox_replicas" {
  description = "Nombre de réplicas NetBox"
  type        = number
  default     = 2
}

variable "netbox_namespace" {
  description = "Namespace Kubernetes pour NetBox"
  type        = string
  default     = "netbox"
}

# ---- DÉPLOIEMENT EN DEUX PHASES ----

variable "deploy_phase_2" {
  description = "Activer la phase 2 (addons EKS, pod identity, déploiements K8s). Mettre à false pour le premier apply (phase 1 = infra de base)."
  type        = bool
  default     = false
}
