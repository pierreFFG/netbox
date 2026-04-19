# NetBox Deployment Runbook (Court)

Runbook rapide pour deploiement/reprise NetBox dans `TestNetbox`.

## 1) Pre-checks

- Se placer dans le projet:
  - `cd netbox_infra` (depuis la racine du repository)
- Verifier profil:
  - `AWS_PROFILE=TestNetbox aws sts get-caller-identity`
- Verifier Terraform:
  - `AWS_PROFILE=TestNetbox terraform init`
  - `AWS_PROFILE=TestNetbox terraform validate`

## 2) Variables critiques (tfvars)

Verifier dans `terraform.tfvars`:

- `account_id = "629068383519"`
- `deploy_phase_2 = true`
- `rds_master_username = "netboxadmin"`
- `rds_db_name = "ORCL"`
- `rds_storage_type = "gp3"`
- `rds_max_allocated_storage > rds_allocated_storage`

## 3) Appliquer l'infra

- Deploy complet:
  - `AWS_PROFILE=TestNetbox terraform apply -var-file=terraform.tfvars`

Si lock:
- `terraform force-unlock <LOCK_ID>`
- Relancer apply.

## 4) Verifier NetBox (post-apply)

- `AWS_PROFILE=TestNetbox kubectl get deploy,pods -n netbox -o wide`
- Etat attendu:
  - `deployment-netbox` = `2/2`
  - `deployment-netbox-worker` = `1/1`

## 5) Checks fonctionnels

- Logs web:
  - `AWS_PROFILE=TestNetbox kubectl logs -n netbox deploy/deployment-netbox --tail=120`
- Logs worker:
  - `AWS_PROFILE=TestNetbox kubectl logs -n netbox deploy/deployment-netbox-worker --tail=120`

## 6) Si echec "secret RDS inaccessible"

Symptome:
- `AccessDeniedException ... secretsmanager:GetSecretValue ... rds!db-...`

Actions:
- Verifier secret ARN courant:
  - `AWS_PROFILE=TestNetbox terraform output -raw rds_secret_arn`
- Reappliquer policy Pod Identity:
  - `AWS_PROFILE=TestNetbox terraform apply -var-file=terraform.tfvars -target=module.eks_config -auto-approve`
- Redemarrer pods netbox:
  - `AWS_PROFILE=TestNetbox kubectl rollout restart deployment/deployment-netbox -n netbox`
  - `AWS_PROFILE=TestNetbox kubectl rollout restart deployment/deployment-netbox-worker -n netbox`

## 7) Si DB incoherente (rare)

Utiliser seulement en environnement test:

- Scale down web/worker:
  - `AWS_PROFILE=TestNetbox kubectl scale deployment -n netbox deployment-netbox --replicas=0`
  - `AWS_PROFILE=TestNetbox kubectl scale deployment -n netbox deployment-netbox-worker --replicas=0`
- Recreate RDS force:
  - `AWS_PROFILE=TestNetbox terraform apply -var-file=terraform.tfvars -target=module.rds -replace=module.rds.aws_db_instance.rds_db -auto-approve`
- Reappliquer complet:
  - `AWS_PROFILE=TestNetbox terraform apply -var-file=terraform.tfvars`

## 8) Parametres techniques deja en place (durables)

- `DB_USER` utilise pour les credentials DB
- `DB_SSLMODE=require` + `PGSSLMODE=require`
- `SKIP_SUPERUSER=true`
- Probes NetBox en TCP (stables en bootstrap)
- IAM Pod Role autorise `arn:aws:secretsmanager:...:secret:rds!*`

## 9) Fichiers de reference

- Detail complet des changements:
  - `NETBOX_DEPLOYMENT_FIXES.md`

