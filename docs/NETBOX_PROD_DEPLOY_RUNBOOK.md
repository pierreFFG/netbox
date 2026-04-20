# NetBox - Runbook de deploiement PROD (Step-by-step)

Ce runbook decrit un processus de deploiement prod qui limite le risque et evite de redeployer la base RDS dans le flux normal.

## Principes

- Stack DB/foundation et stack applicative doivent etre decouplees.
- En deploiement applicatif standard, **aucun changement RDS** n'est autorise.
- Les migrations NetBox sont executees de facon controlee (job unique), pas en parallele.
- Chaque etape a un gate de validation avant de passer a la suivante.

---

## 0) Preconditions (avant fenetre de deploiement)

- Acces AWS prod valide (profil/role).
- `kubectl` pointe sur le cluster prod.
- Image NetBox candidate deja push dans ECR prod.
- Sauvegarde DB/PITR verifiee.
- Changement approuve.

Verification rapide:

```bash
aws sts get-caller-identity
kubectl cluster-info
```

---

## 1) Preparer et valider le plan Terraform

Depuis le dossier `netbox_infra`:

```bash
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars -out=plan.prod.bin
```

### Gate 1 - blocage DB

Le plan ne doit pas contenir de `replace`/`destroy` sur `module.rds.*`.

Commande de controle:

```bash
terraform show -no-color plan.prod.bin | rg "module\.rds|-/\+|destroy"
```

Attendu:
- aucun remplacement/destruction RDS.
- si RDS apparait en changement destructif: **STOP** (runbook DB separé obligatoire).

---

## 2) Mettre l'app en mode maintenance controlee

Objectif: eviter les ecritures concurrentes pendant migration.

Option simple:
- scale worker a 0 temporairement
- garder le web en lecture/maintenance selon politique d'exploitation

```bash
kubectl scale deployment -n netbox deployment-netbox-worker --replicas=0
kubectl get deploy -n netbox
```

---

## 3) Appliquer Terraform (app uniquement)

```bash
terraform apply plan.prod.bin
```

### Gate 2

- apply termine sans erreur.
- aucun drift critique sur ressources app.

---

## 4) Executer la migration DB en mode unique

Ne pas laisser plusieurs pods migrer en parallele.

Approche recommandee:
- lancer un Job one-shot `manage.py migrate --no-input`
- attendre completion du job

Exemple generique:

```bash
kubectl apply -f k8s/jobs/netbox-migrate-job.yaml
kubectl wait --for=condition=complete job/netbox-migrate -n netbox --timeout=900s
kubectl logs -n netbox job/netbox-migrate --tail=200
```

### Gate 3

- Job migration termine `Complete`.
- aucun traceback Django/DB.

---

## 5) Demarrer web puis worker

1) Web d'abord:

```bash
kubectl scale deployment -n netbox deployment-netbox --replicas=2
kubectl rollout status deployment/deployment-netbox -n netbox --timeout=600s
```

2) Puis worker:

```bash
kubectl scale deployment -n netbox deployment-netbox-worker --replicas=1
kubectl rollout status deployment/deployment-netbox-worker -n netbox --timeout=300s
```

### Gate 4

- `deployment-netbox` = `2/2`
- `deployment-netbox-worker` = `1/1`

```bash
kubectl get deploy,pods -n netbox -o wide
```

---

## 6) Validation post-deploiement

Checks minimum:

```bash
kubectl logs -n netbox deploy/deployment-netbox --tail=150
kubectl logs -n netbox deploy/deployment-netbox-worker --tail=150
```

Verifier:
- pas d'erreur DB auth/SSL
- pas d'erreur secretsmanager access denied
- pas de crashloop pods

Checks applicatifs:
- endpoint NetBox OK
- login admin de service OK
- creation/lecture d'un objet test OK

---

## 7) Rollback applicatif (si incident)

### 7.1 Rollback deployment K8s

```bash
kubectl rollout undo deployment/deployment-netbox -n netbox
kubectl rollout undo deployment/deployment-netbox-worker -n netbox
kubectl rollout status deployment/deployment-netbox -n netbox --timeout=300s
kubectl rollout status deployment/deployment-netbox-worker -n netbox --timeout=300s
```

### 7.2 Si migration incompatible

- stop app (web/worker) temporairement
- restaurer backup DB selon procedure DBA
- redeployer version applicative precedente

> Les actions DB (restore/PITR) suivent un runbook DB separe et approuve.

---

## 8) Runbook DB separé (quand necessaire uniquement)

Changements comme:
- remplacement RDS
- changement engine majeur
- operation destructive

ne doivent **pas** etre traites dans ce runbook applicatif.

Ils exigent:
- fenetre dediee
- snapshot/backup valide
- plan de retour arriere DB
- validation securite/compliance

---

## 9) Checklist finale (Go/No-Go)

- [ ] Plan Terraform valide
- [ ] Aucun changement destructif sur `module.rds.*`
- [ ] Migration executee une seule fois et complete
- [ ] Web `2/2` et worker `1/1`
- [ ] Tests fonctionnels passes
- [ ] Monitoring sans alertes critiques 15-30 min

---

## Notes d'implementation utiles

- Garder en place les protections deja ajoutees:
  - `DB_USER` (pas `DB_USERNAME`)
  - `DB_SSLMODE=require` + `PGSSLMODE=require`
  - IAM Pod Identity autorisant `secret:rds!*`
  - probes stables et coherentes avec le comportement runtime NetBox
- Eviter les patchs manuels en prod; preferer Terraform/module versionne.

