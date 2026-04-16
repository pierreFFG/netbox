# Explication détaillée — Branche feature/netbox-infra-test
## Dossier netbox_infra/ — Fichier par fichier

---

## Vue d'ensemble

Le déploiement se fait en **2 phases** contrôlées par la variable `deploy_phase_2` :

- **Phase 1** (`deploy_phase_2 = false`) : Crée toute l'infrastructure AWS (EKS, RDS, Redis, S3, KMS, ECR, certificats, CloudTrail, alarmes). Les providers Kubernetes/Helm pointent vers `localhost` (inactifs).
- **Phase 2** (`deploy_phase_2 = true`) : Après que l'infra existe, on active les déploiements Kubernetes (namespace, addons, pod identity, deployment NetBox, ingress, worker).

On fait `terraform apply` deux fois : une fois en phase 1, puis on passe `deploy_phase_2 = true` et on refait `terraform apply`.

---

## Ordre de lecture recommandé

```
1. backend.tf      → Où Terraform stocke son état
2. variables.tf    → Toutes les entrées configurables
3. terraform.tfvars → Les valeurs concrètes
4. provider.tf     → Comment Terraform se connecte à AWS et K8s
5. data.tf         → Données dynamiques du compte
6. local.tf        → Calculs internes et configurations dérivées
7. main.tf         → Les 10 modules qui créent l'infrastructure
8. app_secret.tf   → Secrets applicatifs NetBox
9. cccs_compliance.tf → Conformité CCCS (CloudTrail, logs, alarmes)
10. eks_addons.tf  → Addons Kubernetes (CSI drivers, metrics)
11. netbox_k8s.tf  → Déploiement de l'application NetBox dans K8s
12. outputs.tf     → Ce que Terraform expose après le déploiement
```

---

## 1. backend.tf — Fondations Terraform

**But** : Définir les versions des plugins et où stocker l'état Terraform.

### Providers requis (5)

| Provider | Version | Rôle |
|----------|---------|------|
| `aws` | ~> 5.94.1 | Créer les ressources AWS (RDS, EKS, S3, etc.) |
| `kubectl` | >= 1.14.0 | Appliquer des manifestes YAML bruts sur Kubernetes |
| `kubernetes` | >= 2.0.0 | Gérer les ressources K8s natives (namespace, configmap) |
| `helm` | ~> 2.12 | Installer des charts Helm (addons EKS) |
| `random` | ~> 3.6 | Générer les mots de passe sécurisés |

### Backend S3

```
Bucket : tf-backend-629068383519-ca-central-1
Clé    : netbox/terraform.tfstate
```

Le state Terraform (la cartographie de toutes les ressources créées) est stocké dans S3, chiffré, avec verrouillage (`use_lockfile`) pour empêcher 2 personnes de modifier l'infra en même temps.

### Lien avec les autres fichiers
- Tous les fichiers dépendent de `backend.tf` car c'est lui qui charge les providers.
- Le bucket S3 doit exister avant le premier `terraform init`.

---

## 2. variables.tf — Les entrées configurables

**But** : Déclarer toutes les variables que l'utilisateur doit fournir. Aucune ressource n'est créée ici.

### Catégories de variables (30 variables)

**Générales (4)** : `region`, `projet` (netbox00), `palier` (test), `environment` (Test)
- `palier` est utilisé dans les noms de ressources (ex: `netbox00-media-test`)
- `environment` est utilisé dans les tags SQSS

**Réseau (2)** : `vpc_id`, `private_subnet_ids`
- Le VPC et les subnets sont partagés via AWS RAM depuis le compte Network. On ne les crée pas, on les référence.

**EKS (10)** : `cluster_name`, `k8s_version`, `cluster_oidc_id`, `eks_admin_role_arn`, `eks_cluster_role_name`, `eks_node_role_name`, `node_pools`, `nodepool_name`, `nodeclass_name`, `capacity_type`, `instance_categories`, `architecture`
- `cluster_oidc_id` est vide en phase 1 (le cluster n'existe pas encore). Il est renseigné en phase 2 après la création du cluster.

**ECR (1)** : `repositories` — liste d'objets décrivant les repos Docker à créer

**RDS (5)** : `rds_identifier`, `rds_instance_class`, `rds_engine_version` (15.10), `rds_allocated_storage` (100 Go), `rds_backup_retention_period` (30j)

**Redis (2)** : `redis_cluster_name`, `redis_node_type`

**Tags SQSS (6)** : `dic`, `nom_equipe`, `nom_etab`, `nom_actif_informationel`, `account_id`, `classification`

**DNS/Certificats (3)** : `hosted_zone_id`, `hosted_zone_type`, `domain_zone`

**NetBox App (3)** : `netbox_image_tag` (v4.1.4), `netbox_replicas` (2), `netbox_namespace` (netbox)

**Déploiement (1)** : `deploy_phase_2` (false/true) — le switch entre les 2 phases

### Lien avec les autres fichiers
- `terraform.tfvars` fournit les valeurs concrètes
- Toutes les variables sont consommées par `main.tf`, `provider.tf`, `local.tf`, etc.

---

## 3. terraform.tfvars — Les valeurs concrètes

**But** : Remplir les variables avec les valeurs spécifiques au compte test.

Points importants :
- Les valeurs réseau (`vpc_id`, `private_subnet_ids`) sont en placeholder `XXXX` — à remplacer avec les vraies valeurs du compte 629068383519
- `deploy_phase_2 = false` — on commence par la phase 1
- `k8s_version = "1.35"` — version Kubernetes très récente
- `rds_engine_version = "15.10"` — PostgreSQL 15 (pas 16)
- `netbox_image_tag = "v4.1.4"` — NetBox v4.1.4 (pas v4.2.3)
- Les credentials Docker Hub ne sont pas dans le tfvars (ils sont en dur dans `main.tf`)

### Lien avec les autres fichiers
- Alimente `variables.tf` qui alimente tout le reste

---

## 4. provider.tf — Les connexions

**But** : Configurer comment Terraform parle à AWS et à Kubernetes.

### Provider AWS
- Région `ca-central-1`, 5 retries
- `default_tags` : 11 tags SQSS appliqués automatiquement à toutes les ressources

### Mécanisme des 2 phases (le point clé)

```
Phase 1 (deploy_phase_2 = false) :
  - data SSM : count = 0 → pas de lecture SSM
  - providers K8s : host = "https://localhost" → inactifs
  - Résultat : seules les ressources AWS sont créées

Phase 2 (deploy_phase_2 = true) :
  - data SSM : count = 1 → lit l'endpoint et le CA du cluster EKS
  - providers K8s : host = endpoint réel → connectés au cluster
  - Résultat : les ressources Kubernetes sont créées
```

C'est l'astuce centrale du code. Sans ça, le premier `terraform apply` planterait car les providers K8s essaieraient de se connecter à un cluster qui n'existe pas encore.

### 4 providers configurés
1. **AWS** — toujours actif
2. **kubernetes** — actif en phase 2 seulement
3. **kubectl** — actif en phase 2 seulement
4. **helm** — actif en phase 2 seulement

### Lien avec les autres fichiers
- Les data SSM lisent les paramètres créés par `module "eks"` dans `main.tf`
- Les providers K8s sont utilisés par `netbox_k8s.tf`, `eks_addons.tf`, `app_secret.tf`

---

## 5. data.tf — Données dynamiques

**But** : Récupérer des informations du compte AWS au moment de l'exécution.

```hcl
data "aws_region" "current" {}          → "ca-central-1"
data "aws_caller_identity" "current" {} → account_id = "629068383519"
```

### Lien avec les autres fichiers
- `local.tf` utilise ces data pour construire `local.account_id` et `local.region`
- Évite de mettre l'account_id en dur partout

---

## 6. local.tf — Calculs internes

**But** : Centraliser les valeurs calculées et les configurations complexes. C'est le "cerveau" du code.

### Valeurs calculées

| Local | Valeur | Usage |
|-------|--------|-------|
| `account_id` | 629068383519 | Noms de buckets S3, ARN |
| `region` | ca-central-1 | ARN, registre ECR |
| `domain_zone` | netbox00.aws.sante.quebec | Certificats, ingress |
| `registre_ecr` | 629068383519.dkr.ecr.ca-central-1.amazonaws.com | Images Docker des addons |
| `rds_host` | (extrait de module.rds.rds_endpoint) | ConfigMap NetBox |

### Pod Identity (pod_identities)

Définit un seul pod identity `netbox` avec une policy IAM qui autorise les pods à :
1. **Lire les secrets** : `secretsmanager:GetSecretValue` sur `netbox-*` et le secret RDS auto-géré
2. **Déchiffrer** : `kms:Decrypt` sur la clé KMS NetBox et la clé KMS RDS
3. **Accéder à S3** : `s3:GetObject/PutObject/DeleteObject/ListBucket` sur le bucket media

C'est la policy la plus importante du code : elle définit exactement ce que les pods NetBox ont le droit de faire dans AWS.

### ConfigMap NetBox (netbox_configmap_data)

Variables d'environnement non-sensibles injectées dans les pods :
- `DB_HOST`, `DB_PORT`, `DB_NAME` → connexion PostgreSQL
- `REDIS_HOST`, `REDIS_PORT` → connexion Redis
- `ALLOWED_HOSTS` → `["*"]` (accepte toutes les requêtes)
- `TIME_ZONE` → `America/Toronto`

### Lien avec les autres fichiers
- `pod_identities` → consommé par `module "eks_config"` dans `main.tf`
- `netbox_configmap_data` → consommé par `kubernetes_config_map` dans `app_secret.tf`
- `rds_host` → dépend de `module.rds` dans `main.tf`
- `registre_ecr` → utilisé par `eks_addons.tf` pour les images Docker

---

## 7. main.tf — Le cœur de l'infrastructure (10 modules)

**But** : Appeler les modules partagés pour créer toute l'infrastructure AWS.

### Module 1 : ECR (Elastic Container Registry)

```
Source : SanteQuebec.Terraform.Modules//ecr
```

Crée le repo Docker `netbox-image` pour stocker l'image NetBox. Le cluster EKS étant privé (pas d'accès Internet), les images doivent être dans ECR.

- `tag_mutability = "MUTABLE"` — les tags peuvent être écrasés (contrairement à notre code qui avait IMMUTABLE)
- Configure aussi un pull-through cache Docker Hub avec les credentials en dur

### Module 2 : KMS (keyForNetbox)

```
Source : SanteQuebec.Terraform.Modules//kms
Alias  : alias/keyForNetbox
```

Crée une clé de chiffrement CMK. Utilisée pour chiffrer :
- Le bucket S3 media
- Le bucket S3 CloudTrail
- Le secret applicatif NetBox
- (La clé RDS est gérée séparément par le module RDS)

### Module 3 : EKS (Cluster Kubernetes)

```
Source : SanteQuebec.Terraform.Modules//eks
Nom    : netbox00-eks-test
```

Crée le cluster EKS avec :
- Version K8s 1.35
- Déployé dans les 2 subnets privés RAM
- Rôles IAM pour le control plane et les noeuds
- Stocke l'endpoint et le CA dans SSM (utilisés par `provider.tf` en phase 2)

### Module 4 : EKS Node (Karpenter)

```
Source : SanteQuebec.Terraform.Modules//eks_node
```

Configure Karpenter pour provisionner les noeuds automatiquement :
- `on-demand`, `amd64`, familles `c/r/m`
- Tags SQSS sur les instances EC2
- `depends_on = [module.eks]` — attend que le cluster existe

### Module 5 : EKS Config (Pod Identity) — Phase 2 uniquement

```
Source : SanteQuebec.Terraform.Modules//eks_config
Condition : for_each = var.deploy_phase_2 ? local.pod_identities : {}
```

Crée le rôle IAM et l'association Pod Identity pour le namespace `netbox` et le service account `netbox-sa`. En phase 1, le `for_each` est vide donc rien n'est créé.

### Module 6 : RDS (PostgreSQL)

```
Source : SanteQuebec.Terraform.Modules//rds
Nom    : netbox00-rds-postgres-test
```

Crée l'instance PostgreSQL 15.10 avec :
- `db.t3.large`, 100 Go gp3
- Backups 30 jours, Performance Insights activé
- **2 règles ingress** (c'est un point important) :
  1. Port 5432 depuis `10.0.0.0/8` (tout le réseau LZA)
  2. Port 5432 depuis le Security Group du control plane EKS (plus restrictif)
- Le module crée aussi automatiquement un secret RDS dans Secrets Manager avec le username/password

### Module 7 : Redis

```
Source : SanteQuebec.Terraform.Modules//redis
Nom    : netbox-redis-test
```

Crée le cluster Redis 7.0 avec :
- `cache.t3.medium`, Multi-AZ
- `maxmemory_policy = "allkeys-lru"` — quand la mémoire est pleine, Redis supprime les clés les moins récemment utilisées
- Snapshots 7 jours
- **1 règle ingress** : port 6379 depuis le SG du control plane EKS uniquement (pas le CIDR LZA)
- `depends_on = [module.eks]`

### Module 8 : S3 Media

```
Source : SanteQuebec.Terraform.Modules//s3
Nom    : netbox00-media-test
```

Bucket S3 pour stocker les fichiers uploadés dans NetBox (images, pièces jointes). Chiffré avec la clé KMS, versioning activé.

### Module 9 : Certificats ACM

```
Source : SanteQuebec.Terraform.Modules//certificats
Domaine : netbox.test.netbox00.aws.sante.quebec
```

Crée un certificat SSL/TLS via AWS Certificate Manager pour le domaine NetBox. La validation se fait par DNS (enregistrement CNAME dans Route 53). Le certificat est ensuite attaché à l'ALB via l'ingress Kubernetes.

### Lien avec les autres fichiers
- `module.rds` → ses outputs sont utilisés par `local.tf` (rds_host) et `app_secret.tf` (rds_secret_arn)
- `module.redis_netbox` → ses outputs sont utilisés par `local.tf` (redis_endpoint)
- `module.eks` → ses SSM parameters sont utilisés par `provider.tf`
- `module.keyForNetbox` → sa clé est utilisée par `app_secret.tf` et `cccs_compliance.tf`
- `module.certificat_netbox` → son ARN est utilisé par `netbox_k8s.tf` (ingress)

---

## 8. app_secret.tf — Secrets applicatifs NetBox

**But** : Générer les secrets propres à l'application NetBox et créer le ConfigMap Kubernetes.

### 3 mots de passe générés

| Ressource | Longueur | Usage |
|-----------|----------|-------|
| `netbox_secret_key` | 50 chars | Clé secrète Django (signe les sessions, cookies, CSRF) |
| `superuser_password` | 24 chars | Mot de passe du compte admin NetBox |
| `superuser_api_token` | 40 chars | Token pour l'API REST NetBox |

### Secret Secrets Manager : `netbox-app-secret`

Stocke les 3 valeurs ci-dessus en JSON, chiffré avec la clé KMS. C'est le secret que le SPC `netbox-app-spc` va lire pour injecter les variables dans les pods.

### ConfigMap Kubernetes : `netbox-config` (Phase 2 uniquement)

Crée un ConfigMap avec les variables non-sensibles (DB_HOST, REDIS_HOST, etc.) définies dans `local.netbox_configmap_data`. Le `count = var.deploy_phase_2 ? 1 : 0` garantit qu'il n'est créé qu'en phase 2.

### Lien avec les autres fichiers
- Le secret `netbox_app` est référencé par `netbox_k8s.tf` (SPC `netbox-app-spc`)
- Le ConfigMap est référencé par le deployment NetBox dans `netbox_k8s.tf`
- La clé KMS vient de `module.keyForNetbox` dans `main.tf`
- Les données du ConfigMap viennent de `local.tf`

---

## 9. cccs_compliance.tf — Conformité CCCS-Medium

**But** : Créer les ressources de logging, audit et monitoring exigées par la conformité CCCS-Medium.

### CloudWatch Log Groups Redis (2)

- `/aws/elasticache/netbox-redis-test/slow-log` — requêtes Redis lentes
- `/aws/elasticache/netbox-redis-test/engine-log` — logs du moteur Redis

Ces log groups doivent exister avant que Redis ne tente d'y écrire.

### S3 CloudTrail + CloudTrail

- Bucket `netbox00-cloudtrail-{account_id}` chiffré KMS avec bucket policy pour CloudTrail
- Trail `netbox00-trail` multi-région avec validation des fichiers de log
- Capture tous les événements de management + les accès S3

Note : la LZA a déjà un CloudTrail organisationnel (`AWSAccelerator-Organizations-CloudTrail`). Ce trail supplémentaire donne une granularité spécifique à NetBox.

### S3 ALB Logs

- Bucket `netbox00-alb-logs-{account_id}` chiffré AES256 (pas KMS, car ALB l'exige)
- Bucket policy autorise le service ELB et le service de livraison de logs à écrire

### CloudWatch Alarms (3)

| Alarme | Métrique | Seuil |
|--------|----------|-------|
| `netbox-rds-high-cpu` | CPU RDS | > 80% pendant 10 min |
| `netbox-rds-low-storage` | Espace libre RDS | < 5 Go |
| `netbox-redis-high-cpu` | CPU Redis | > 80% pendant 10 min |

### Lien avec les autres fichiers
- Les log groups Redis sont utilisés par `module.redis_netbox` dans `main.tf`
- Le bucket ALB logs est référencé par l'ingress dans `netbox_k8s.tf`
- La clé KMS vient de `module.keyForNetbox` dans `main.tf`

---

## 10. eks_addons.tf — Addons Kubernetes (Phase 2 uniquement)

**But** : Installer les composants système nécessaires dans le cluster EKS via Helm.

`count = var.deploy_phase_2 ? 1 : 0` — créé uniquement en phase 2.

### 3 addons installés

**1. secrets-store-csi-driver (v1.4.0)**
- Le driver CSI qui permet de monter des secrets AWS comme des volumes dans les pods
- `syncSecret.enabled = true` — synchronise les secrets AWS vers des Secrets Kubernetes
- `enableSecretRotation = true` — détecte les changements de secrets et les met à jour
- Toutes les images Docker pointent vers l'ECR privé (pas Docker Hub)

**2. secrets-store-csi-provider-aws (v1.0.1)**
- Le provider spécifique AWS pour le driver CSI ci-dessus
- C'est lui qui sait parler à AWS Secrets Manager
- Image depuis l'ECR privé

**3. metrics-server (v3.12.2)**
- Collecte les métriques CPU/mémoire des pods
- Nécessaire pour que le HPA (Horizontal Pod Autoscaler) fonctionne
- Image depuis l'ECR privé

### IRSA Role

Crée un rôle IRSA (IAM Role for Service Account) `secrets-store-irsa` qui autorise le service account `secret-store-csi-sa` à lire les secrets et paramètres SSM.

### Lien avec les autres fichiers
- `local.registre_ecr` (de `local.tf`) est utilisé pour les URLs des images
- Dépend de `module.eks` dans `main.tf`
- Le CSI driver est nécessaire pour que les SPC dans `netbox_k8s.tf` fonctionnent

---

## 11. netbox_k8s.tf — Déploiement de NetBox (Phase 2 uniquement)

**But** : Déployer l'application NetBox dans le cluster EKS. C'est le fichier le plus complexe.

### Namespace Kubernetes

Crée le namespace `netbox` avec les labels `app=netbox` et `environment=test`.

### Module netbox_app

```
Source : SanteQuebec.Terraform.Modules//k8s_config_apps//netbox_app
Branche : feature/netbox-app-module (pas master !)
```

Ce module crée en interne :

**Deployment web** (2 réplicas) :
- Image : `{account_id}.dkr.ecr.ca-central-1.amazonaws.com/netbox-image:v4.1.4`
- Port 8080
- Resources : 250m-500m CPU, 512Mi-1Gi RAM
- Probes : readiness à 45s, liveness à 90s sur `/api/`
- ConfigMap `netbox-config` monté comme variables d'environnement

**Deployment worker** (1 réplica) :
- Même image mais commande différente : `python manage.py rqworker`
- Traite les tâches asynchrones (webhooks, rapports, scripts custom)
- Resources plus légères : 100m-250m CPU, 256Mi-512Mi RAM

**Service** : `service-netbox` port 80 → target 8080, type IP

**2 SecretProviderClass (SPC)** :
- `netbox-rds-spc` → lit le secret RDS auto-géré → injecte `DB_USERNAME` et `DB_PASSWORD`
- `netbox-app-spc` → lit `netbox-app-secret` → injecte `SECRET_KEY`, `SUPERUSER_PASSWORD`, `SUPERUSER_API_TOKEN`

**Ingress ALB** :
- Classe : `eks-auto-alb` (ALB créé automatiquement par EKS)
- Scheme : interne
- Domaine : `netbox.test.netbox00.aws.sante.quebec`
- Certificat ACM attaché
- ALB group : `test-netbox`
- Access logs vers le bucket S3 ALB logs
- Deletion protection activée
- Headers invalides rejetés

**Topology Spread** :
- `min_domains = 2` — les pods sont répartis sur au moins 2 AZ
- `when_unsatisfiable = "ScheduleAnyway"` — si impossible, schedule quand même (pas de blocage)

### Chaîne de dépendances

```
module.eks_config (pod identity)
module.rds (base de données)
module.redis_netbox (cache)
module.certificat_netbox (certificat SSL)
kubernetes_namespace.netbox
kubernetes_config_map.netbox_config
aws_secretsmanager_secret_version.netbox_app
    └── Tout doit exister AVANT que netbox_app soit créé
```

### Lien avec les autres fichiers
- Consomme les outputs de presque tous les autres fichiers
- C'est le "consommateur final" de toute l'infrastructure

---

## 12. outputs.tf — Ce que Terraform expose

**But** : Rendre accessibles les informations clés après le déploiement.

| Output | Source | Usage |
|--------|--------|-------|
| `rds_endpoint` | module.rds | Pour se connecter à PostgreSQL |
| `rds_secret_arn` | module.rds | ARN du secret RDS auto-géré |
| `redis_endpoint` | module.redis_netbox | Pour se connecter à Redis |
| `redis_port` | module.redis_netbox | Port Redis (6379) |
| `redis_secret_arn` | module.redis_netbox | ARN du secret Redis |
| `s3_media_bucket` | module.s3_netbox_media | Nom du bucket media |
| `certificate_arns` | module.certificat_netbox | ARN du certificat ACM |
| `dns_validation_records` | module.certificat_netbox | CNAME pour valider le certificat |
| `netbox_app_secret_arn` | aws_secretsmanager_secret.netbox_app | ARN du secret applicatif |
| `netbox_url` | calculé | `https://netbox.test.netbox00.aws.sante.quebec` |
| `cloudtrail_arn` | aws_cloudtrail.netbox | ARN du CloudTrail |
| `alb_logs_bucket` | module.s3_alb_logs | Bucket des logs ALB |
| `cloudtrail_bucket` | module.s3_cloudtrail | Bucket CloudTrail |

---

## Comment les fichiers s'interconnectent

```
terraform.tfvars
    └── variables.tf
         └── provider.tf (tags SQSS, connexion AWS)
         └── data.tf (account_id, region)
              └── local.tf (calculs, policies, configmap)
                   └── main.tf (10 modules)
                        ├── module.ecr → ECR
                        ├── module.keyForNetbox → KMS
                        │    └── app_secret.tf (chiffre le secret)
                        │    └── cccs_compliance.tf (chiffre CloudTrail)
                        ├── module.eks → EKS cluster
                        │    └── provider.tf (SSM → providers K8s)
                        │    └── module.eks_node (Karpenter)
                        │    └── module.eks_config (Pod Identity)
                        │    └── eks_addons.tf (CSI drivers, metrics)
                        ├── module.rds → PostgreSQL
                        │    └── local.tf (rds_host → configmap)
                        │    └── netbox_k8s.tf (SPC rds)
                        ├── module.redis_netbox → Redis
                        │    └── local.tf (redis_endpoint → configmap)
                        ├── module.s3_netbox_media → S3 media
                        │    └── local.tf (policy S3 pour pods)
                        └── module.certificat_netbox → ACM
                             └── netbox_k8s.tf (ingress)

app_secret.tf (secret + configmap)
    └── netbox_k8s.tf (SPC app + configmap ref)

cccs_compliance.tf (CloudTrail, logs, alarmes)
    └── netbox_k8s.tf (ALB logs bucket ref)

netbox_k8s.tf (namespace + module netbox_app)
    └── outputs.tf (URL, ARNs)
```

---

## Procédure de déploiement

```bash
# Phase 1 : Infrastructure AWS
# deploy_phase_2 = false dans terraform.tfvars
terraform init
terraform plan
terraform apply
# → Crée : EKS, RDS, Redis, S3, KMS, ECR, certificats, CloudTrail, alarmes

# Récupérer le cluster_oidc_id
aws eks describe-cluster --name netbox00-eks-test --query "cluster.identity.oidc.issuer" --output text
# Extraire l'ID et le mettre dans terraform.tfvars

# Phase 2 : Déploiements Kubernetes
# deploy_phase_2 = true dans terraform.tfvars
# cluster_oidc_id = "XXXXX" dans terraform.tfvars
terraform plan
terraform apply
# → Crée : namespace, addons, pod identity, deployment NetBox, worker, ingress, configmap
```
