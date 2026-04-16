provider "aws" {
  region      = var.region
  max_retries = 5
  default_tags {
    tags = {
      createur                      = "Terraform"
      SQSS_region                   = "ca-central-1"
      SQSS_cloud                    = "AWS"
      SQSS_coteDIC                  = var.dic
      SQSS_environnement            = var.environment
      SQSS_equiperesponsable        = var.nom_equipe
      SQSS_etablissementresponsable = var.nom_etab
      SQSS_proprietaireactif        = var.nom_actif_informationel
      SQSS_nomsystemeapplication    = var.nom_actif_informationel
      SQSS_abonnement               = var.account_id
      SQSS_classification           = var.classification
    }
  }
}

# SSM Parameters créés par le module EKS (disponibles après phase 1)
data "aws_ssm_parameter" "eks_certificate" {
  count = var.deploy_phase_2 ? 1 : 0
  name  = "/eks/${var.cluster_name}/certificate-authority-data"
}

data "aws_ssm_parameter" "eks_endpoint" {
  count = var.deploy_phase_2 ? 1 : 0
  name  = "/eks/${var.cluster_name}/endpoint"
}

# Providers K8s configurés uniquement en phase 2
provider "kubernetes" {
  host                   = var.deploy_phase_2 ? data.aws_ssm_parameter.eks_endpoint[0].value : "https://localhost"
  cluster_ca_certificate = var.deploy_phase_2 ? base64decode(data.aws_ssm_parameter.eks_certificate[0].value) : ""
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = var.deploy_phase_2 ? ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region] : ["version"]
    command     = var.deploy_phase_2 ? "aws" : "kubectl"
  }
}

provider "kubectl" {
  host                   = var.deploy_phase_2 ? data.aws_ssm_parameter.eks_endpoint[0].value : "https://localhost"
  cluster_ca_certificate = var.deploy_phase_2 ? base64decode(data.aws_ssm_parameter.eks_certificate[0].value) : ""
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = var.deploy_phase_2 ? ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region] : ["version"]
    command     = var.deploy_phase_2 ? "aws" : "kubectl"
  }
}

provider "helm" {
  kubernetes {
    host                   = var.deploy_phase_2 ? data.aws_ssm_parameter.eks_endpoint[0].value : "https://localhost"
    cluster_ca_certificate = var.deploy_phase_2 ? base64decode(data.aws_ssm_parameter.eks_certificate[0].value) : ""
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = var.deploy_phase_2 ? ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region] : ["version"]
      command     = var.deploy_phase_2 ? "aws" : "kubectl"
    }
  }
}
