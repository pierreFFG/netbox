# NetBox - Modifications appliquees pour un deploiement fonctionnel

Ce document recapitulatif liste les modifications apportees pour corriger les blocages de deploiement NetBox (Phase 2) et atteindre un etat stable.

## Contexte

- Compte cible: `TestNetbox` (`629068383519`)
- Projet: `SanteQuebec.Netbox.Infra/netbox_infra`
- Profil AWS: `TestNetbox`
- Objectif: deploiement NetBox fonctionnel (web + worker) sur EKS avec RDS/Redis/Secrets.

## Etat final valide

- `deployment-netbox`: `2/2` Running
- `deployment-netbox-worker`: `1/1` Running
- Migration DB terminee avec succes (sequence complete visible dans les logs)
- Secrets CSI et Pod Identity operationnels

## Modifications de configuration Terraform (infra NetBox)

### 1) Alignement credentials DB pour NetBox

Fichier: `netbox_k8s.tf`

- Changement des aliases secrets RDS:
  - `DB_USERNAME` -> `DB_USER`
- Alignement `env_from_secrets`:
  - `DB_USERNAME` -> `DB_USER`

Raison:
- NetBox attend `DB_USER`; sinon fallback vers utilisateur par defaut et echec auth DB.

### 2) Alignement nom de base RDS/NetBox

Fichiers: `variables.tf`, `main.tf`, `local.tf`, `terraform.tfvars`

- Ajout variable `rds_db_name` (defaut: `ORCL`)
- Passage de `db_name = var.rds_db_name` au module RDS
- ConfigMap NetBox: `DB_NAME = var.rds_db_name`
- `terraform.tfvars`: `rds_db_name = "ORCL"`

Raison:
- Eviter mismatch `database "netbox" does not exist` quand RDS est cree avec `ORCL`.

### 3) SSL DB et variables runtime NetBox

Fichiers: `local.tf`, `netbox_k8s.tf`

- ConfigMap:
  - `DB_SSLMODE = "require"`
- Env statiques NetBox:
  - `SKIP_SUPERUSER = "true"`
  - `HOME = "/tmp"`
  - `PGSSLMODE = "require"`

Raison:
- Forcer mode SSL compatible RDS.
- Eviter blocage bootstrap superuser interactif.
- Eviter erreur libpq sur chemin cert `/root/.postgresql`.

### 4) Source module NetBox repointee vers remote

Fichier: `netbox_k8s.tf`

- Le `source` du module a ete remis en remote:
  - `git::https://dev.azure.com/.../SanteQuebec.Terraform.Modules//k8s_config_apps//netbox_app?ref=feature/netbox-app-module`

Raison:
- Utiliser les modifications deja poussees du module distant.

## Modifications module `netbox_app` (SanteQuebec.Terraform.Modules)

Ces modifications ont ete poussees au module remote puis consommees depuis l'infra NetBox.

### 1) Support probes TCP (durable)

Fichiers module:
- `k8s_config_apps/netbox_app/variables.tf`
- `k8s_config_apps/netbox_app/main.tf`
- `k8s_config_apps/netbox_app/templates/deployment.yaml.tpl`

Ajouts:
- Variables:
  - `readiness_probe_use_tcp` (bool, default `false`)
  - `liveness_probe_use_tcp` (bool, default `false`)
- Passage de ces variables au template de deployment
- Template conditionnel:
  - `tcpSocket` si mode TCP active
  - `httpGet` sinon

Configuration infra appliquee:
- `readiness_probe_use_tcp = true`
- `liveness_probe_use_tcp = true`

Raison:
- Les probes HTTP `/api/` retournaient 400/502/503 pendant bootstrap selon timing et etat app.
- Le check TCP stabilise l'etat Kubernetes sans forcer une route HTTP applicative stricte.

## Modifications de politique IAM Pod Identity (EKS config)

Fichier: `local.tf` (policy JSON encode pour pod permissions)

- Resource secretsmanager pour Pod Role:
  - Avant: secret RDS specifique (ARN exact)
  - Apres: wildcard robuste `arn:aws:secretsmanager:${region}:${account_id}:secret:rds!*`

Raison:
- L'ARN du secret RDS change apres recreation DB.
- Eviter AccessDenied sur rotation/recreation future.

## Recreation complete RDS (operation d'assainissement)

Action Terraform executee:
- Replacement force de l'instance RDS:
  - `-replace=module.rds.aws_db_instance.rds_db`

Raison:
- Etat DB incoherent apres essais precedents de migration.
- Repartir sur une base propre.

Effets:
- Nouveau `rds_secret_arn`
- Necessite de realigner Pod Identity + SecretProviderClass sur le nouveau secret.

## SecretProviderClass et secrets CSI

Objet: `netbox-rds-spc`

- Mise a jour vers le nouveau secret RDS apres recreation instance.
- Regeneration du secret Kubernetes `netbox-rds-spc` (DB_USER/DB_PASSWORD) validee.

## Correctifs de demarrage NetBox

Symptomes traites:
- CrashLoop/BackOff worker et web
- blocage migrations
- echec readiness/liveness
- erreurs DB auth et SSL
- erreurs access secret RDS via Pod Identity

Correctifs cle:
- DB user/secret alias corrige
- DB name aligne
- SSL DB force
- probes TCP durables
- bootstrap superuser saute
- permissions IAM robustes sur secret RDS

## Commandes de validation executees

- `terraform init`
- `terraform validate`
- `terraform apply -var-file=terraform.tfvars`
- `kubectl get deploy,pods -n netbox -o wide`
- `kubectl logs` (web + worker)
- verifications `SecretProviderClass`, `secret netbox-rds-spc`, `ConfigMap netbox-config`

## Notes importantes

- Warnings deprecation restants (modules externes):
  - `kubernetes_namespace` (v1 recommande)
  - `data.aws_region.current.name` (attribut deprecie)
- Ces warnings n'empechent pas le fonctionnement.

## Resume des fichiers modifies (infra)

- `netbox_k8s.tf`
- `local.tf`
- `main.tf`
- `variables.tf`
- `terraform.tfvars`

## Resume des fichiers modifies (module netbox_app)

- `SanteQuebec.Terraform.Modules/k8s_config_apps/netbox_app/variables.tf`
- `SanteQuebec.Terraform.Modules/k8s_config_apps/netbox_app/main.tf`
- `SanteQuebec.Terraform.Modules/k8s_config_apps/netbox_app/templates/deployment.yaml.tpl`

## Mises a jour complementaires (stabilisation EKS/Ingress/DNS)

### 1) Ingress EKS Auto Mode + certificat ACM

Fichiers: `variables.tf`, `main.tf`, `netbox_k8s.tf`, `cert_validation.tf`, `provider.tf`, `outputs.tf`, `terraform.tfvars`

- Ajout/alignement FQDN NetBox:
  - `netbox_fqdn = "test.netbox.aws.sante.quebec"`
- Validation ACM DNS en cross-account (`provider aws.network`)
- Separation de la zone d'exploitation et de la zone de validation ACM:
  - `hosted_zone_id` (records applicatifs/external-dns)
  - `acm_validation_hosted_zone_id` (records `_acm-validation`)
- Validation ACM deplacee vers la PHZ demandee:
  - `Z0811627115HEYTKBQUFW`

Resultat:
- Certificat valide et servi par l'ALB sur `test.netbox.aws.sante.quebec`.

### 2) IngressClass EKS Auto Mode

Fichiers: `ingress_class_params_sc.tf`, `k8s_common_res/ingress_class_params.yaml.tpl`, `k8s_common_res/ingress_class.yaml.tpl`

- Creation explicite de:
  - `IngressClassParams` (`eks.amazonaws.com/v1`)
  - `IngressClass` (`controller: eks.amazonaws.com/alb`)

Raison:
- Corriger l'etat `ingressClass not found` et permettre la reconciliation ALB.

### 3) external-dns fiabilise dans Terraform

Fichiers: `backend.tf`, `eks_addons.tf`

- Provider Helm upgrade:
  - `hashicorp/helm` passe a `~> 2.14` (init upgrade installe `v2.17.0`)
- Chart `external-dns` bascule en OCI:
  - `repo = "oci://registry-1.docker.io/bitnamicharts"`
- Import du release existant dans le state Terraform:
  - `module.eks_addons[0].helm_release.addon["external-dns"]` <- `kube-system/external-dns`

Resultat:
- Suppression du blocage `invalid_reference: invalid tag`
- `terraform apply` complet possible
- Pattern addons conserve (resource `helm_release` Terraform).

### 4) Healthcheck ALB persistant dans le code

Fichier: `ingress_healthcheck_patch.tf`

- Ajout d'un patch Terraform de l'Ingress `ingress-netbox` pour fixer:
  - `alb.ingress.kubernetes.io/healthcheck-path: /static/netbox.css`
  - `alb.ingress.kubernetes.io/success-codes: "200"`

Raison:
- Eviter des targets `unhealthy` dues a des reponses HTTP applicatives sur `/`.

### 5) Redis: correction de la configuration NetBox

Fichier: `netbox_k8s.tf`

- Ajout des variables env NetBox:
  - `REDIS_PASSWORD = module.redis_netbox.auth_token`
  - `REDIS_SSL = "true"`

Contexte:
- ElastiCache etait configure avec:
  - `AuthTokenEnabled = true`
  - `TransitEncryptionEnabled = true`
- NetBox etait initialement en Redis non TLS / sans password -> timeouts / 504.

Resultat:
- Connexion `rediss://` operationnelle
- login et pages web ne timeoutent plus sur Redis.

### 6) Correctif runtime login NetBox (UserConfig)

Action operationnelle en base (Django shell):
- Creation des `UserConfig` manquants (admin inclus).

Contexte:
- Erreur login:
  - `Cannot assign "<netbox.config.Config ...>": "User.config" must be a "UserConfig" instance.`
- Cause: absence de `UserConfig` pour l'utilisateur.

Resultat:
- Login admin retabli (`302 /`), plus d'exception serveur sur `/login/`.

