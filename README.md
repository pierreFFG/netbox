# SanteQuebec.Netbox.Infra

Infrastructure Terraform pour le déploiement de **NetBox** sur AWS dans la Landing Zone Accelerator (LZA) de Santé Québec.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│           AWS ca-central-1 - Compte TestNetbox              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  ALB (Ingress EKS Auto) - HTTPS/TLS                │    │
│  │  Certificat ACM : netbox.dev.netbox00.aws.sante.qc │    │
│  │  Access logs → S3, deletion protection              │    │
│  └──────────────────────┬──────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────▼──────────────────────────────┐    │
│  │  EKS Cluster (netbox00-eks-dev)                     │    │
│  │  ├─ Deployment: netbox (2 replicas, multi-AZ)       │    │
│  │  ├─ Deployment: netbox-worker (1 replica, rqworker) │    │
│  │  ├─ Service: ClusterIP → port 8080                  │    │
│  │  ├─ Ingress: ALB internal                           │    │
│  │  └─ 2x SPC: netbox-rds-spc + netbox-app-spc        │    │
│  └──────────┬──────────────────────┬───────────────────┘    │
│             │                      │                         │
│  ┌──────────▼──────────┐  ┌───────▼────────────────────┐   │
│  │  RDS PostgreSQL     │  │  ElastiCache Redis         │   │
│  │  (Multi-AZ)         │  │  (Multi-AZ, auth token)    │   │
│  │  Engine: 15.10      │  │  Engine: 7.0               │   │
│  │  Backup: 30 jours   │  │  Snapshots: 7 jours        │   │
│  └─────────────────────┘  └────────────────────────────┘   │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌─────────────────────────┐   │
│  │ S3 média │  │ KMS      │  │ Secrets Manager         │   │
│  │ chiffré  │  │ rotation │  │ RDS auto + app secret   │   │
│  └──────────┘  └──────────┘  └─────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  CCCS: CloudTrail + ALB logs + CloudWatch Alarms    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Structure du projet

```
SanteQuebec.Netbox.Infra/
├── README.md
├── netbox/                            # Documentation et guides CCCS (référence)
└── netbox_infra/                      # Code Terraform modulaire (DÉPLOIEMENT)
    ├── backend.tf                     # Backend S3 + providers requis
    ├── provider.tf                    # Providers AWS, K8s, Helm, kubectl
    ├── variables.tf                   # Variables d'entrée
    ├── terraform.tfvars               # Valeurs (à personnaliser)
    ├── data.tf                        # Data sources
    ├── local.tf                       # Locals (pod identity, configmap data)
    ├── main.tf                        # Modules infra (EKS, RDS, Redis, S3, KMS, ECR, Certificats)
    ├── eks_addons.tf                  # Addons EKS (CSI drivers, metrics-server)
    ├── app_secret.tf                  # Secrets Manager + ConfigMap
    ├── netbox_k8s.tf                  # Module netbox_app (Deployment, Worker, Service, Ingress, SPC)
    ├── cccs_compliance.tf             # CCCS: CloudTrail, ALB logs, alarmes CloudWatch
    ├── outputs.tf                     # Outputs
    └── .gitignore
```

## Modules Terraform utilisés

Tous les modules proviennent du repo `SanteQuebec.Terraform.Modules` :

| Module | Branche | Usage |
|--------|---------|-------|
| `ecr` | master | Registre d'images Docker |
| `kms` | master | Clé de chiffrement (rotation auto) |
| `eks` | master | Cluster EKS |
| `eks_node` | master | NodePool Karpenter |
| `eks_config` | master | Pod Identity (IAM ↔ ServiceAccount) |
| `eks_addons` | master | CSI drivers, metrics-server |
| `rds` | master | PostgreSQL 15.10 |
| `redis` | master | ElastiCache Redis 7.0 |
| `s3` | master | Bucket médias NetBox |
| `certificats` | master | Certificats ACM |
| `k8s_config_apps/netbox_app` | feature/netbox-app-module | Deployment NetBox (web + worker + SPC + Ingress) |

## Déploiement initial

### 1. Personnaliser `terraform.tfvars`

Remplacer les valeurs `XXXX` :
- `vpc_id`, `private_subnet_ids` → console AWS du compte TestNetbox
- `account_id` → ID du compte TestNetbox
- `eks_admin_role_arn` → ARN du rôle SSO SystemAdministrator
- `hosted_zone_id` → ID de la zone Route53

### 2. Créer le bucket S3 backend

```bash
aws s3 mb s3://tf-backend-testnetbox-ca-central-1 --region ca-central-1
aws s3api put-bucket-versioning \
  --bucket tf-backend-testnetbox-ca-central-1 \
  --versioning-configuration Status=Enabled
```

### 3. Déployer

```bash
cd netbox_infra

# === PHASE 1 : Infrastructure de base ===
# deploy_phase_2 = false dans terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Récupérer le cluster_oidc_id depuis la console AWS ou via :
# aws eks describe-cluster --name netbox00-eks-test --query "cluster.identity.oidc.issuer" --output text | rev | cut -d'/' -f1 | rev

# === PHASE 2 : Config K8s ===
# Mettre à jour terraform.tfvars :
#   deploy_phase_2 = true
#   cluster_oidc_id = "<valeur récupérée>"
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Vérifier

```bash
aws eks update-kubeconfig --region ca-central-1 --name netbox00-eks-dev
kubectl get pods -n netbox
kubectl get svc -n netbox
kubectl get ingress -n netbox
```

## Accès à NetBox

- URL : `https://netbox.dev.netbox00.aws.sante.quebec`
- Admin : `admin` / mot de passe dans Secrets Manager (`netbox-app-secret` → `superuser_password`)
- API Token : dans Secrets Manager (`netbox-app-secret` → `superuser_api_token`)

## Conformité CCCS-Medium

- Région : `ca-central-1` uniquement
- Chiffrement au repos : KMS (RDS, S3, Secrets Manager, Redis)
- Chiffrement en transit : TLS (Redis auth token, ALB HTTPS redirect)
- Tags SQSS : appliqués via `default_tags` du provider
- Secrets : AWS Secrets Manager + CSI Driver (pas de secrets en clair)
- Audit : CloudTrail dédié avec bucket S3 chiffré KMS
- Logging : ALB access logs, Redis slow-log/engine-log, CloudWatch
- Monitoring : Alarmes CloudWatch (RDS CPU/stockage, Redis CPU)
- RDS : Multi-AZ, backup 30 jours, Performance Insights, Enhanced Monitoring
- Redis : Multi-AZ, failover automatique, snapshots 7 jours
- S3 : Versioning activé, accès public bloqué, chiffrement KMS
