# Explication détaillée — Branche feature/netbox-infra-test
## Dossier netbox_infra/ — Fichier par fichier
### Dernière mise à jour : commit 0b29083 ("plusieurs fixes")

---

## Vue d'ensemble

Le déploiement se fait en **2 phases** contrôlées par la variable `deploy_phase_2` :

- **Phase 1** (`deploy_phase_2 = false`) : Crée toute l'infrastructure AWS (EKS, RDS, Redis, S3, KMS, ECR, certificats, CloudTrail, alarmes, IngressClass). Les providers K8s pointent vers `localhost` (inactifs).
- **Phase 2** (`deploy_phase_2 = true`) : Active les déploiements Kubernetes (Karpenter nodes, addons, pod identity, deployment NetBox, ingress, worker, ConfigMaps, S3 media config).

On fait `terraform apply` deux fois : une fois en phase 1, puis on passe `deploy_phase_2 = true` et on refait `terraform apply`.

### État actuel du déploiement

Le tfvars montre `deploy_phase_2 = true` et `cluster_oidc_id` est renseigné → **les deux phases ont été exécutées**. L'infra est complète.

---

## Liste des fichiers (17 fichiers)

```
netbox_infra/
├── backend.tf                    # Providers requis + backend S3
├── provider.tf                   # Connexion AWS + K8s + provider Network
├── data.tf                       # Données dynamiques + validation compte
├── variables.tf                  # 40+ variables d'entrée
├── terraform.tfvars              # Valeurs concrètes (compte 629068383519)
├── local.tf                      # Calculs, policies IAM, ConfigMap
├── main.tf                       # 9 modules (ECR, KMS, EKS, nodes, config, RDS, Redis, S3, certificats)
├── app_secret.tf                 # Secrets applicatifs + ConfigMap K8s
├── cert_validation.tf            # Validation DNS ACM cross-account
├── cccs_compliance.tf            # CloudTrail, logs Redis, alarmes CloudWatch
├── eks_addons.tf                 # Addons Helm (CSI driver, metrics, external-dns)
├── ingress_class_params_sc.tf    # IngressClass + IngressClassParams ALB
├── ingress_healthcheck_patch.tf  # Patch ingress pour health check
├── netbox_k8s.tf                 # Déploiement NetBox (web + worker + ingress)
├── netbox_s3_media.tf            # ConfigMap extra.py pour stockage S3
├── outputs.tf                    # 13 sorties
├── scripts/copy_ecr_images.sh    # Script copie images Docker vers ECR
├── k8s_common_res/               # Templates YAML pour IngressClass
│   ├── ingress_class.yaml.tpl
│   └── ingress_class_params.yaml.tpl
└── docs/                         # Documentation interne
    ├── NETBOX_DEPLOYMENT_FIXES.md
    ├── NETBOX_DEPLOYMENT_RUNBOOK.md
    ├── NETBOX_PROD_DEPLOY_RUNBOOK.md
    └── NETBOX_SYSTEM_DESIGN.md
```

---

## 1. backend.tf — Fondations Terraform

**But** : Verrouiller les versions des plugins et configurer le stockage de l'état.

### Changements depuis le commit initial

| Élément | Avant | Maintenant |
|---------|-------|------------|
| Provider AWS | ~> 5.94.1 | >= 6.40.0 |
| Provider Helm | (absent) | ~> 2.14 |

Le passage à AWS provider 6.x est un changement majeur (nouvelle version majeure).

### Backend S3

```
Bucket : tf-backend-629068383519-ca-central-1 (existe déjà ✅)
Clé    : netbox/terraform.tfstate
```

---

## 2. provider.tf — Les connexions

**But** : Configurer les 5 providers (AWS, AWS Network, Kubernetes, kubectl, Helm).

### Nouveauté : Provider AWS "network"

```hcl
provider "aws" {
  alias   = "network"
  region  = var.region
  profile = var.dns_validation_aws_profile  # "Network"
}
```

Ce deuxième provider AWS se connecte au **compte Network (841162671396)** via un profil AWS CLI séparé. Il est utilisé par `cert_validation.tf` pour créer les enregistrements DNS de validation ACM dans la zone Route 53 du compte Network.

### Nouveauté : Tag SQSS_recherche

Ajouté dans les `default_tags` : `SQSS_recherche = "non"` (en dur).

### Mécanisme des 2 phases (inchangé)

- Phase 1 : providers K8s pointent vers `localhost` (inactifs)
- Phase 2 : providers K8s lisent SSM et se connectent au cluster EKS

---

## 3. data.tf — Données dynamiques + Validation

**But** : Récupérer les infos du compte et valider qu'on est sur le bon compte.

### Nouveauté : Check de validation

```hcl
check "aws_account_target_validation" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.account_id
    error_message = "Le compte AWS courant ne correspond pas à var.account_id"
  }
}
```

Si tu exécutes Terraform avec le mauvais profil AWS, il affiche un warning au lieu de déployer sur le mauvais compte. C'est une sécurité importante.

---

## 4. variables.tf — Les entrées (40+ variables)

**But** : Déclarer toutes les variables configurables.

### Nouvelles variables ajoutées

| Variable | Défaut | Rôle |
|----------|--------|------|
| `rds_max_allocated_storage` | 200 | Autoscaling stockage RDS (max 200 Go) |
| `rds_storage_type` | gp3 | Type de stockage RDS |
| `rds_master_username` | netboxadmin | Username master RDS |
| `rds_db_name` | ORCL | Nom de la base PostgreSQL |
| `acm_validation_hosted_zone_id` | "" | Zone Route 53 pour validation DNS ACM |
| `dns_validation_aws_profile` | Network | Profil AWS du compte qui héberge la zone DNS |
| `external_dns_assume_role_arn` | arn:...external-dns-role | Rôle assumé par external-dns |
| `netbox_fqdn` | test.netbox.aws.sante.quebec | FQDN complet de NetBox |
| `ingress_class_name` | eks-auto-alb | Classe d'ingress EKS |
| `scheme` | internal | Type d'ALB (interne) |
| `alb_logs_bucket_name` | (requis) | Bucket S3 centralisé pour logs ALB |
| `alb_logs_prefix` | alb-logs | Préfixe dans le bucket |

### Variables supprimées

`domain_filters`, `domain_filter_enabled` → remplacées par la config inline dans `eks_addons.tf`.

---

## 5. terraform.tfvars — Valeurs concrètes

**But** : Les valeurs réelles du compte 629068383519.

### Changements majeurs

| Paramètre | Avant | Maintenant |
|-----------|-------|------------|
| `private_subnet_ids` | XXXX placeholder | Vrais IDs des subnets |
| `vpc_id` | XXXX placeholder | `vpc-0841e283345d9925f` |
| `account_id` | XXXX | `629068383519` |
| `eks_admin_role_arn` | XXXX | ARN réel SSO |
| `cluster_oidc_id` | "" | `71533274C5CD8191A7DD2BE829AF5D69` |
| `deploy_phase_2` | false | **true** (les 2 phases sont faites) |
| `hosted_zone_id` | XXXX | `Z03223882T7MQ3KRV58KY` |
| `acm_validation_hosted_zone_id` | (nouveau) | `Z0811627115HEYTKBQUFW` |
| `domain_zone` | netbox00.aws.sante.quebec | `aws.sante.quebec` |
| `netbox_fqdn` | (nouveau) | `test.netbox.aws.sante.quebec` |
| `alb_logs_bucket_name` | (nouveau) | `aws-accelerator-elb-access-logs-324037318411-ca-central-1` |
| `alb_logs_prefix` | (nouveau) | `alb-logs/netbox00-test` |
| `rds_db_name` | (nouveau) | `ORCL` |
| `rds_max_allocated_storage` | (nouveau) | 200 |
| `rds_storage_type` | (nouveau) | gp3 |
| `rds_master_username` | (nouveau) | netboxadmin |
| `dns_validation_aws_profile` | (nouveau) | Network |

Les logs ALB sont maintenant envoyés vers un bucket centralisé du compte LogArchive (`324037318411`), pas un bucket local.

---

## 6. local.tf — Calculs internes

### Changements

| Élément | Avant | Maintenant |
|---------|-------|------------|
| `region` | `data.aws_region.current.name` | `data.aws_region.current.region` |
| Policy Secrets Manager | `module.rds.rds_secret_arn` | `arn:...secret:rds!*` (wildcard) |
| Policy KMS | Decrypt, DescribeKey | + `Encrypt`, `GenerateDataKey` |
| ConfigMap `DB_NAME` | "netbox" (en dur) | `var.rds_db_name` (variable) |
| ConfigMap `DB_SSLMODE` | (absent) | `"require"` |
| ConfigMap `ALLOWED_HOSTS` | `["*"]` (JSON) | `"*"` (string simple) |

Le `DB_SSLMODE = "require"` force la connexion chiffrée entre NetBox et PostgreSQL.

---

## 7. main.tf — Les 9 modules

### Changements par module

**module "eks_node"** : Ajout de `count = var.deploy_phase_2 ? 1 : 0`. Les noeuds Karpenter ne sont créés qu'en phase 2 (le cluster doit exister d'abord).

**module "rds"** :
- Ajout de `db_name`, `max_allocated_storage`, `type_stockage`, `db_username` (nouvelles variables)
- Les ingress rules RDS utilisent maintenant `concat()` avec une condition : la règle SG EKS n'est ajoutée qu'en phase 2 (quand le SG EKS existe)

**module "redis_netbox"** : Les ingress rules sont conditionnelles (`var.deploy_phase_2 ? [...] : []`). En phase 1, pas de règle SG car le SG EKS n'existe pas encore.

**module "certificat_netbox"** :
- `domain_zone` changé de `local.domain_zone` à `local.domain_zone`
- `aws_region` changé de `data.aws_region.current.name` à `data.aws_region.current.region`
- Le domaine utilise maintenant `var.netbox_fqdn` au lieu d'être calculé

---

## 8. app_secret.tf — Secrets applicatifs

### Changements

- `kubernetes_config_map` → `kubernetes_config_map_v1` (API v1 explicite)
- Le ConfigMap dépend maintenant de `module.eks_config` au lieu de `kubernetes_namespace.netbox`

---

## 9. cert_validation.tf — NOUVEAU : Validation DNS ACM cross-account

**But** : Automatiser la validation DNS des certificats ACM en créant les enregistrements CNAME dans la zone Route 53 du compte Network.

### Comment ça fonctionne

```
1. module "certificat_netbox" crée le certificat ACM (statut PENDING_VALIDATION)
2. ACM fournit des enregistrements CNAME à créer pour prouver la propriété du domaine
3. cert_validation.tf utilise le provider "aws.network" pour créer ces CNAME
   dans la zone Route 53 du compte Network (Z0811627115HEYTKBQUFW)
4. ACM vérifie les CNAME → certificat passe en statut ISSUED
5. aws_acm_certificate_validation attend que la validation soit complète
```

La condition `enable_acm_dns_validation` vérifie que `acm_validation_hosted_zone_id` ressemble à un vrai ID Route 53 (commence par Z). Si c'est vide, la validation est désactivée.

---

## 10. cccs_compliance.tf — Conformité CCCS

### Changements

Le bucket S3 ALB logs local a été **supprimé**. Les logs ALB sont maintenant envoyés vers le bucket centralisé du compte LogArchive :
```
aws-accelerator-elb-access-logs-324037318411-ca-central-1/alb-logs/netbox00-test/
```

Le reste est inchangé : CloudWatch log groups Redis, CloudTrail S3 + trail, 3 alarmes CloudWatch.

---

## 11. eks_addons.tf — Addons Kubernetes

### Changements

**Nouvel addon : external-dns**

external-dns surveille les ingress Kubernetes et crée/met à jour automatiquement les enregistrements DNS dans Route 53.

| Paramètre | Valeur |
|-----------|--------|
| Image | `bitnami/external-dns:v0.20.0` (depuis ECR privé) |
| Provider | AWS Route 53 |
| Policy | `upsert-only` (crée/met à jour, ne supprime jamais) |
| Domain filter | `aws.sante.quebec` |
| Zone filter | `Z03223882T7MQ3KRV58KY` |
| Assume role | `arn:aws:iam::841162671396:role/external-dns-role` |

external-dns assume un rôle dans le compte Network pour gérer les enregistrements DNS. Quand l'ingress NetBox est créé avec l'annotation `external-dns.alpha.kubernetes.io/hostname: test.netbox.aws.sante.quebec.`, external-dns crée automatiquement l'enregistrement A/CNAME dans Route 53.

**Nouvel IRSA role : external-dns-irsa**

Autorise le service account `external-dns-sa` à assumer le rôle cross-account dans le compte Network.

**Autre changement** : metrics-server image tag passé de `v0.7.2` à `v0.8.1`.

**Dépendance** : `depends_on` inclut maintenant `module.eks_node[0]` (les noeuds doivent exister pour installer les addons).

---

## 12. ingress_class_params_sc.tf — NOUVEAU : IngressClass ALB

**But** : Configurer la classe d'ingress pour EKS Auto Mode ALB.

Crée 2 ressources Kubernetes via des templates YAML :

1. **IngressClassParams** : définit le scheme de l'ALB (`internal`)
2. **IngressClass** : `eks-auto-alb` qui référence les params ci-dessus

Sans ces ressources, EKS ne sait pas quel type d'ALB créer quand un ingress est déployé.

---

## 13. ingress_healthcheck_patch.tf — NOUVEAU : Patch Health Check

**But** : Corriger le health check de l'ALB après le déploiement initial.

Le module `netbox_app` crée l'ingress avec un health check sur `/api/`. Ce patch le remplace par `/static/netbox.css` qui est un fichier statique plus léger et plus fiable pour le health check ALB.

Il ajoute aussi le `success-codes: "200"` explicitement.

Phase 2 uniquement (`count = var.deploy_phase_2 ? 1 : 0`).

---

## 14. netbox_k8s.tf — Déploiement NetBox

### Changements

**Source du module** : passé de `ref=feature/netbox-app-module` à `ref=master` (le module a été mergé).

**Namespace** : la création du namespace `kubernetes_namespace.netbox` a été **supprimée** de ce fichier. Elle est maintenant gérée par le module `netbox_app` ou par `eks_config`.

**Probes** :
- `readiness_probe_initial_delay` : 45 → **120** secondes
- `liveness_probe_initial_delay` : 90 → **300** secondes
- Ajout de `readiness_probe_use_tcp = true` et `liveness_probe_use_tcp = true` (TCP probe au lieu de HTTP)

**Env vars secrets** : `DB_USERNAME` renommé en `DB_USER` (pour correspondre à la config NetBox).

**Nouveaux env vars statiques** :
| Variable | Valeur | Rôle |
|----------|--------|------|
| `SKIP_SUPERUSER` | true | Ne pas recréer le superuser à chaque démarrage |
| `HOME` | /tmp | Répertoire home pour le processus NetBox |
| `PGSSLMODE` | require | Force SSL vers PostgreSQL |
| `REDIS_PASSWORD` | `module.redis_netbox.auth_token` | Token auth Redis |
| `REDIS_SSL` | true | Force SSL vers Redis |

**Ingress** :
- `certificate_arns` et `alb_extra_attributes` utilisent maintenant les variables (`var.alb_logs_bucket_name`, `var.alb_logs_prefix`) au lieu de valeurs calculées
- `topology_spread_when_unsatisfiable` : `ScheduleAnyway` → **`DoNotSchedule`** (plus strict : refuse de scheduler si les contraintes multi-AZ ne sont pas respectées)

**Nouveau paramètre** : `extra_configmap_name = "netbox-extra-config"` — référence le ConfigMap S3 media.

**Dépendances** : ajout de `kubectl_manifest.ingress_class` (l'IngressClass doit exister avant l'ingress).

---

## 15. netbox_s3_media.tf — NOUVEAU : Configuration S3 pour médias

**But** : Configurer NetBox pour stocker les fichiers uploadés (images, pièces jointes) dans S3 au lieu du filesystem local.

Crée un ConfigMap `netbox-extra-config` contenant un fichier Python `extra.py` :

```python
STORAGE_BACKEND = "storages.backends.s3boto3.S3Boto3Storage"
STORAGE_CONFIG = {
    "AWS_STORAGE_BUCKET_NAME": "netbox00-media-test",
    "AWS_S3_REGION_NAME": "ca-central-1",
    "AWS_S3_ADDRESSING_STYLE": "virtual",
    "AWS_DEFAULT_ACL": None,
}
```

Ce fichier est monté dans le pod NetBox et chargé par Django au démarrage. NetBox utilise alors S3 comme backend de stockage au lieu du disque local (qui serait perdu au redémarrage du pod).

---

## 16. outputs.tf — Sorties

### Changements

- `netbox_url` : calculé dynamiquement avec `var.netbox_fqdn` au lieu de `var.palier` + `var.domain_zone`
- `alb_logs_bucket` : pointe vers `var.alb_logs_bucket_name` (bucket centralisé) au lieu du module S3 local

---

## 17. scripts/copy_ecr_images.sh — NOUVEAU : Script copie images

**But** : Copier toutes les images Docker nécessaires vers l'ECR du compte NetBox.

Le cluster EKS est privé sans accès Internet direct. Les images Docker doivent être dans l'ECR local. Ce script :

1. S'authentifie sur l'ECR source (compte ProdSitesWeb 349139558736) et destination (629068383519)
2. Crée les repos ECR dans le compte destination
3. Copie l'image NetBox depuis Docker Hub → ECR
4. Copie 8 images d'addons depuis l'ECR source → ECR destination :
   - CSI Secrets Store driver + CRDs
   - CSI node driver registrar
   - Liveness probe
   - Secrets Store CSI provider AWS
   - Metrics server + addon resizer
   - External DNS

---

## Comment les fichiers s'interconnectent

```
terraform.tfvars
    └── variables.tf
         └── provider.tf
         │    ├── AWS provider (tags SQSS)
         │    ├── AWS provider "network" (validation DNS ACM)
         │    └── K8s/kubectl/Helm providers (phase 2)
         └── data.tf (account_id + validation)
              └── local.tf (policies, configmap, ECR registry)
                   └── main.tf (9 modules)
                        ├── module.ecr → ECR repos
                        ├── module.keyForNetbox → KMS
                        │    └── app_secret.tf (chiffre le secret)
                        │    └── cccs_compliance.tf (chiffre CloudTrail)
                        ├── module.eks → EKS cluster
                        │    ├── provider.tf (SSM → providers K8s)
                        │    ├── module.eks_node (Karpenter, phase 2)
                        │    ├── module.eks_config (Pod Identity, phase 2)
                        │    └── eks_addons.tf (CSI, metrics, external-dns, phase 2)
                        ├── module.rds → PostgreSQL
                        │    ├── local.tf (rds_host → configmap)
                        │    └── netbox_k8s.tf (SPC rds)
                        ├── module.redis_netbox → Redis
                        │    ├── local.tf (redis_endpoint → configmap)
                        │    └── netbox_k8s.tf (auth_token → env var)
                        ├── module.s3_netbox_media → S3 media
                        │    ├── local.tf (policy S3 pour pods)
                        │    └── netbox_s3_media.tf (extra.py configmap)
                        └── module.certificat_netbox → ACM
                             ├── cert_validation.tf (DNS validation cross-account)
                             └── netbox_k8s.tf (ingress certificate_arns)

ingress_class_params_sc.tf (IngressClass + params)
    └── netbox_k8s.tf (depends_on ingress_class)

ingress_healthcheck_patch.tf (patch health check)
    └── depends_on module.netbox_app

app_secret.tf (secret + configmap)
    └── netbox_k8s.tf (SPC app + configmap ref)

cccs_compliance.tf (CloudTrail, logs, alarmes)

netbox_k8s.tf (module netbox_app : web + worker + service + ingress)
    └── outputs.tf

scripts/copy_ecr_images.sh (exécuté manuellement avant phase 2)
```

---

## Procédure de déploiement

```bash
# 0. Copier les images Docker vers ECR (une seule fois)
chmod +x scripts/copy_ecr_images.sh
./scripts/copy_ecr_images.sh

# Phase 1 : Infrastructure AWS
# deploy_phase_2 = false dans terraform.tfvars
terraform init
terraform plan
terraform apply
# → Crée : EKS, RDS, Redis, S3, KMS, ECR, certificats, CloudTrail,
#           alarmes, IngressClass, secrets applicatifs

# Récupérer le cluster_oidc_id
aws eks describe-cluster --name netbox00-eks-test \
  --query "cluster.identity.oidc.issuer" --output text
# Extraire l'ID (dernière partie de l'URL) et le mettre dans terraform.tfvars

# Phase 2 : Déploiements Kubernetes
# deploy_phase_2 = true dans terraform.tfvars
# cluster_oidc_id = "71533274C5CD8191A7DD2BE829AF5D69"
terraform plan
terraform apply
# → Crée : Karpenter nodes, addons (CSI, metrics, external-dns),
#           pod identity, deployment NetBox (web + worker),
#           ConfigMaps, ingress ALB, health check patch, S3 media config
```
