# NetBox System Design - `netbox_infra`

Ce document decrit l'architecture cible de la solution NetBox deployee par Terraform, ainsi que les interactions entre les composants AWS/Kubernetes.

## 1) Objectif et perimetre

- Deployer NetBox (web + worker) sur EKS en environnement `test` (pattern reutilisable `dev/test/prod`).
- Exposer NetBox via un ALB interne avec TLS ACM.
- Utiliser RDS PostgreSQL, ElastiCache Redis, S3, Secrets Manager et Pod Identity.
- Gerer DNS applicatif via `external-dns` en PHZ, et validation ACM DNS en zone dediee.

## 2) Vue d'ensemble des composants

- **Terraform root (`netbox_infra`)**: orchestration de tous les modules.
- **EKS**: cluster Kubernetes + node provisioning (Karpenter).
- **NetBox app module**: Deployment web, worker, Service, Ingress, SecretProviderClass.
- **Data layer**:
  - RDS PostgreSQL (donnees metier)
  - Redis (cache + queues RQ)
  - S3 (media/files)
- **Secrets**:
  - AWS Secrets Manager (secret applicatif + secret Redis + secret RDS)
  - CSI Secrets Store + provider AWS (sync vers secrets K8s)
- **Ingress & TLS**:
  - EKS Auto Mode Ingress (`IngressClass` + `IngressClassParams`)
  - ALB interne
  - ACM certificate (`test.netbox.aws.sante.quebec`)
- **DNS**:
  - `external-dns` (records applicatifs dans PHZ NetBox)
  - Route53 cross-account pour validation ACM (provider alias `aws.network`)

## 3) Architecture logique (flux)

1. Client interne -> resolution DNS `test.netbox.aws.sante.quebec` (PHZ)  
2. Client -> ALB interne (HTTPS 443, certificat ACM)  
3. ALB -> target group IP -> `Service` K8s (`service-netbox`) -> pods web NetBox  
4. Pod web NetBox -> RDS PostgreSQL (SSL require)  
5. Pod web + worker -> Redis (`rediss`, auth token)  
6. Pod web -> S3 media bucket (via permissions Pod Identity)  
7. `external-dns` observe Ingress -> ecrit/maintient records Route53 PHZ  
8. Terraform cree records `_acm-validation` dans zone ACM dediee (compte Network)

## 4) Details des plans de controle

### 4.1 Terraform et providers

- **AWS provider principal**: ressources compte `TestNetbox`.
- **AWS provider alias `network`**: operations Route53 cross-account (validation ACM).
- **Kubernetes / Kubectl / Helm providers**:
  - configures dynamiquement via SSM (`/eks/<cluster>/endpoint` + cert CA).
  - auth via `aws eks get-token`.

### 4.2 Phases de deploiement

- `deploy_phase_2 = false`: infra de base (EKS/RDS/Redis/S3/KMS/certificats/secrets).
- `deploy_phase_2 = true`: addons EKS + ressources Kubernetes NetBox + Ingress.

## 5) Design reseau et securite

- ALB type `internal`, target type `ip`.
- Healthcheck ALB force sur `/static/netbox.css` (retour stable 200).
- Security groups:
  - EKS control plane autorise vers RDS:5432 et Redis:6379.
- Redis:
  - `TransitEncryptionEnabled=true`
  - `AuthTokenEnabled=true`
  - NetBox configure avec `REDIS_SSL=true` + `REDIS_PASSWORD`.
- Donnees sensibles en Secrets Manager KMS.

## 6) Design DNS et certificats

- **FQDN applicatif**: `test.netbox.aws.sante.quebec`.
- **Zone applicative (external-dns)**: `hosted_zone_id` (PHZ NetBox).
- **Zone validation ACM**: `acm_validation_hosted_zone_id` (peut etre differente, cross-account).
- `cert_validation.tf`:
  - cree les CNAME de validation ACM via `aws.network`.
  - valide le certificat avec `aws_acm_certificate_validation`.

## 7) Addons EKS et pattern Helm

- Addons geres dans `module.eks_addons`:
  - `secrets-store-csi-driver`
  - `secrets-store-csi-provider-aws`
  - `metrics-server`
  - `external-dns`
- `external-dns`:
  - chart Bitnami en OCI (`oci://registry-1.docker.io/bitnamicharts`)
  - source `ingress`, registre `txt`, policy `upsert-only`
  - `txtOwnerId` par palier (`lower(var.environment)`)
  - assume role cross-account pour Route53 central.

## 8) Composants applicatifs NetBox

- **Deployment web**:
  - 2 replicas
  - probes TCP pour stabilite startup
  - env DB/Redis/secrets injectes
- **Deployment worker**:
  - 1 replica (RQ worker)
  - depend de Redis pour les queues
- **ConfigMap `netbox-config`**:
  - DB host/name/port/sslmode
  - Redis host/port
  - `ALLOWED_HOSTS`

## 9) Risques et points d'attention

- Changement de secret RDS apres recreation DB -> verifier SecretProviderClass/Pod Identity.
- Drift possible si modifications manuelles Ingress non reflechees dans Terraform.
- `txtOwnerId` doit rester coherent pour eviter conflits inter-paliers dans la meme PHZ.
- Certains warnings deprecation proviennent des modules externes (non bloquants).

## 10) Validation operationnelle recommandee

- `terraform plan` puis `terraform apply`.
- `kubectl -n netbox get deploy,pods,ingress,svc`.
- `aws elbv2 describe-target-health` (targets `healthy`).
- `kubectl logs` web/worker (absence timeout Redis/DB).
- `curl -vk https://test.netbox.aws.sante.quebec`.
- Verification Route53:
  - records applicatifs en PHZ NetBox
  - records ACM dans la zone de validation dediee.

## 11) Fichiers Terraform cles

- `main.tf`: orchestration modules infra (EKS, RDS, Redis, S3, certs).
- `netbox_k8s.tf`: deploiement NetBox (web/worker/service/ingress).
- `eks_addons.tf`: addons Helm et IRSA.
- `provider.tf`: providers AWS/K8s/Helm + alias cross-account.
- `cert_validation.tf`: records Route53 ACM + validation.
- `ingress_class_params_sc.tf`: IngressClass EKS Auto Mode.
- `ingress_healthcheck_patch.tf`: healthcheck ALB persistant.
