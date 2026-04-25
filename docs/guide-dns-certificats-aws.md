# 🌐 Guide complet DNS et Certificats - Contexte `aws.sante.quebec`

Ce guide explique le fonctionnement du DNS et des certificats SSL/TLS en utilisant l'infrastructure réelle de `aws.sante.quebec` comme exemple.

---

## 📚 Table des matières
1. [La hiérarchie DNS](#1--la-hiérarchie-dns)
2. [Les types de records DNS](#2--les-types-de-records-dns)
3. [La délégation DNS](#3--la-délégation-dns)
4. [Les certificats SSL/TLS](#4--les-certificats-ssltls)
5. [Votre infrastructure complète](#5--votre-infrastructure-complète)

---

## 🏗️ 1. La hiérarchie DNS

Le DNS fonctionne comme une **arborescence hiérarchique**, similaire à un système de fichiers:

```
                        . (racine)
                        |
                    .quebec (TLD)
                        |
                    sante.quebec
                        |
                  aws.sante.quebec
                        |
            ┌───────────┴───────────┐
            |                       |
    netbox.aws.sante.quebec    autres sous-domaines
            |
    ┌───────┴───────┐
    |               |
prod.netbox    test.netbox
```

### Analogie: Le système postal

- **. (racine)** = Le système postal mondial
- **.quebec** = La province du Québec
- **sante.quebec** = Le ministère de la Santé
- **aws.sante.quebec** = Le département AWS du ministère
- **netbox.aws.sante.quebec** = L'équipe Netbox dans AWS
- **prod.netbox.aws.sante.quebec** = L'environnement de production de Netbox

---

## 📝 2. Les types de records DNS

### 🔵 A (Address Record)
**Rôle:** Pointe un nom de domaine vers une **adresse IPv4**

**Exemple:**
```
www.aws.sante.quebec  →  A  →  192.0.2.1
```

**Cas d'usage:**
- Site web hébergé sur un serveur
- API accessible via une IP
- Serveur d'application

**Dans votre contexte:**
```bash
# Si vous aviez un serveur web pour Netbox
prod.netbox.aws.sante.quebec  →  A  →  10.168.1.50
```

---

### 🔵 AAAA (IPv6 Address Record)
**Rôle:** Pointe un nom de domaine vers une **adresse IPv6**

**Exemple:**
```
www.aws.sante.quebec  →  AAAA  →  2001:0db8::1
```

**Différence avec A:**
- A = IPv4 (32 bits) → `192.0.2.1`
- AAAA = IPv6 (128 bits) → `2001:0db8::1`

**Cas d'usage:** Même chose que A, mais pour les réseaux IPv6 modernes

---

### 🔵 CNAME (Canonical Name)
**Rôle:** Crée un **alias** - redirige un nom vers un autre nom

**Exemple réel de votre infrastructure:**
```
_87409773503dc25331643efae3f95496.prod.netbox.aws.sante.quebec
    ↓ CNAME
_95341ec0860a537b3d7b436362363cb8.jkddzztszm.acm-validations.aws
```

**Analogie:** C'est comme dire "Pour joindre Pierre, appelez Marie"

**Cas d'usage:**
1. **Validation de certificats SSL** (votre cas!)
2. **CDN:** `www.example.com → CNAME → d111111abcdef8.cloudfront.net`
3. **Load Balancer:** `app.example.com → CNAME → my-alb-123456.ca-central-1.elb.amazonaws.com`
4. **Alias simples:** `www.example.com → CNAME → example.com`

**⚠️ Règle importante:** Un CNAME ne peut pas coexister avec d'autres records pour le même nom

---

### 🔵 NS (Name Server)
**Rôle:** Indique **qui est responsable** de répondre aux questions DNS pour une zone

**Exemple réel de votre infrastructure:**
```
Dans la zone: aws.sante.quebec
Record:
netbox.aws.sante.quebec  →  NS  →  ns-1600.awsdns-08.co.uk
                                    ns-638.awsdns-15.net
                                    ns-84.awsdns-10.com
                                    ns-1433.awsdns-51.org
```

**Analogie:** C'est comme dire "Pour toutes les questions sur le département Netbox, contactez ces 4 bureaux"

**Pourquoi 4 serveurs?**
- **Redondance:** Si un serveur tombe, les autres répondent
- **Performance:** Répartition géographique
- **Fiabilité:** AWS garantit la disponibilité

---

### 🔵 TXT (Text Record)
**Rôle:** Stocke du **texte arbitraire** - utilisé pour la vérification et la configuration

**Exemples d'usage:**

1. **Vérification de propriété de domaine:**
```
aws.sante.quebec  →  TXT  →  "google-site-verification=abc123xyz"
```

2. **SPF (anti-spam email):**
```
aws.sante.quebec  →  TXT  →  "v=spf1 include:_spf.google.com ~all"
```

3. **DKIM (signature email):**
```
selector._domainkey.aws.sante.quebec  →  TXT  →  "v=DKIM1; k=rsa; p=MIGfMA0..."
```

4. **DMARC (politique email):**
```
_dmarc.aws.sante.quebec  →  TXT  →  "v=DMARC1; p=quarantine; rua=mailto:dmarc@sante.quebec"
```

---

## 🔗 3. La délégation DNS

### Concept de base

La **délégation** permet de diviser la responsabilité DNS en sous-zones gérées indépendamment.

### Votre cas concret: `aws.sante.quebec` → `netbox.aws.sante.quebec`

#### Avant la délégation (❌ Ne fonctionnait pas):

```
┌─────────────────────────────────────┐
│  Zone: aws.sante.quebec             │
│  Serveurs NS: ns-354.awsdns-...    │
│                                     │
│  Records:                           │
│  - aws.sante.quebec → A → IP       │
│  - www.aws.sante.quebec → ...      │
│                                     │
│  ❌ Pas de délégation pour netbox  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  Zone: netbox.aws.sante.quebec      │
│  Serveurs NS: ns-1600.awsdns-...   │
│                                     │
│  Records:                           │
│  - prod.netbox → CNAME → ...       │
│                                     │
│  ⚠️ Zone orpheline - personne ne    │
│     sait qu'elle existe!            │
└─────────────────────────────────────┘
```

**Problème:** Quand quelqu'un cherche `prod.netbox.aws.sante.quebec`:
1. DNS demande à la zone `aws.sante.quebec`
2. La zone ne sait pas où trouver `netbox.aws.sante.quebec`
3. ❌ Échec de résolution

---

#### Après la délégation (✅ Fonctionne):

```
┌─────────────────────────────────────┐
│  Zone: aws.sante.quebec             │
│  Serveurs NS: ns-354.awsdns-...    │
│                                     │
│  Records:                           │
│  - aws.sante.quebec → A → IP       │
│                                     │
│  ✅ DÉLÉGATION:                     │
│  netbox.aws.sante.quebec → NS →    │
│    - ns-1600.awsdns-08.co.uk       │
│    - ns-638.awsdns-15.net          │
│    - ns-84.awsdns-10.com           │
│    - ns-1433.awsdns-51.org         │
└─────────────────────────────────────┘
              ↓ Délégation
┌─────────────────────────────────────┐
│  Zone: netbox.aws.sante.quebec      │
│  Serveurs NS: ns-1600.awsdns-...   │
│                                     │
│  Records:                           │
│  - prod.netbox → CNAME → ...       │
│  - test.netbox → CNAME → ...       │
│                                     │
│  ✅ Zone déléguée - autonome!       │
└─────────────────────────────────────┘
```

**Maintenant:** Quand quelqu'un cherche `prod.netbox.aws.sante.quebec`:
1. DNS demande à la zone `aws.sante.quebec`
2. La zone répond: "Pour netbox, demandez à ns-1600.awsdns-08.co.uk"
3. DNS demande à `ns-1600.awsdns-08.co.uk`
4. ✅ Obtient la réponse!

---

### Flux de résolution DNS complet

Voici ce qui se passe quand vous tapez `prod.netbox.aws.sante.quebec` dans votre navigateur:

```
1. Votre ordinateur
   ↓ "Quelle est l'IP de prod.netbox.aws.sante.quebec?"
   
2. Serveur DNS récursif (ex: 8.8.8.8)
   ↓ "Je ne sais pas, je vais demander"
   
3. Serveur racine (.)
   ↓ "Pour .quebec, demandez à ns1.quebec"
   
4. Serveur .quebec
   ↓ "Pour sante.quebec, demandez à ns-xyz.awsdns..."
   
5. Serveur sante.quebec
   ↓ "Pour aws.sante.quebec, demandez à ns-abc.awsdns..."
   
6. Serveur aws.sante.quebec
   ↓ "Pour netbox.aws.sante.quebec, demandez à ns-1600.awsdns-08.co.uk"
   ✅ DÉLÉGATION!
   
7. Serveur netbox.aws.sante.quebec (ns-1600.awsdns-08.co.uk)
   ↓ "prod.netbox.aws.sante.quebec → CNAME → xyz.acm-validations.aws"
   
8. Résolution du CNAME...
   ↓ Finalement obtient une IP
   
9. Votre navigateur
   ✅ Se connecte à l'IP!
```

---

## 🔐 4. Les certificats SSL/TLS

### Qu'est-ce qu'un certificat SSL/TLS?

Un certificat SSL/TLS est un **document numérique** qui:
- Prouve que vous êtes le propriétaire d'un domaine
- Permet le chiffrement HTTPS
- Établit la confiance entre le navigateur et le serveur

### Analogie: Le passeport

- **Certificat SSL** = Passeport pour un site web
- **Autorité de certification (CA)** = Gouvernement qui émet les passeports
- **Validation DNS** = Vérification de votre adresse pour obtenir le passeport

---

### Processus de validation DNS avec ACM

Voici exactement ce qui s'est passé pour votre certificat `prod.netbox.aws.sante.quebec`:

#### Étape 1: Demande de certificat
```bash
aws acm request-certificate \
  --domain-name prod.netbox.aws.sante.quebec \
  --validation-method DNS
```

**ACM répond:**
```json
{
  "CertificateArn": "arn:aws:acm:...:certificate/7d912cf7-...",
  "Status": "PENDING_VALIDATION"
}
```

---

#### Étape 2: ACM génère un défi DNS

ACM dit: "Pour prouver que vous contrôlez `prod.netbox.aws.sante.quebec`, créez ce record DNS:"

```
Nom:   _87409773503dc25331643efae3f95496.prod.netbox.aws.sante.quebec
Type:  CNAME
Valeur: _95341ec0860a537b3d7b436362363cb8.jkddzztszm.acm-validations.aws
```

**Pourquoi ce format bizarre?**
- `_87409773503dc25331643efae3f95496` = Hash unique pour ce certificat
- Commence par `_` = Convention pour les records de validation
- `.jkddzztszm.acm-validations.aws` = Serveur de validation d'AWS

---

#### Étape 3: Vous ajoutez le record DNS

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z0811627115HEYTKBQUFW \
  --change-batch file://add-prod-netbox-validation.json
```

**Le record est maintenant dans Route53:**
```
_87409773503dc25331643efae3f95496.prod.netbox.aws.sante.quebec
  → CNAME →
_95341ec0860a537b3d7b436362363cb8.jkddzztszm.acm-validations.aws
```

---

#### Étape 4: ACM vérifie le record

ACM fait périodiquement (toutes les quelques minutes):

```
1. ACM: "Je vais vérifier si le record existe"
   ↓
2. ACM fait une requête DNS:
   nslookup _87409773503dc25331643efae3f95496.prod.netbox.aws.sante.quebec
   ↓
3. DNS répond:
   "C'est un CNAME vers _95341ec0860a537b3d7b436362363cb8.jkddzztszm.acm-validations.aws"
   ↓
4. ACM: "Parfait! C'est bien le record que j'ai demandé!"
   ↓
5. ACM: "Je valide le certificat!"
   ✅ Status: ISSUED
```

---

#### Étape 5: Certificat émis

Une fois validé:
- **Status:** `ISSUED`
- **Validité:** 13 mois (renouvelé automatiquement par AWS)
- **Utilisation:** CloudFront, ALB, API Gateway, etc.

**⚠️ Le record CNAME doit rester en place** pour le renouvellement automatique!

---

### Pourquoi la validation DNS?

Il existe 3 méthodes de validation:

| Méthode | Comment | Avantages | Inconvénients |
|---------|---------|-----------|---------------|
| **DNS** | Ajouter un CNAME | ✅ Automatique<br>✅ Renouvellement auto<br>✅ Pas besoin de serveur web | ❌ Accès DNS requis |
| **Email** | Cliquer sur un lien | ✅ Simple | ❌ Manuel à chaque renouvellement |
| **HTTP** | Fichier sur le serveur | ✅ Simple | ❌ Serveur web requis<br>❌ Manuel |

**AWS recommande DNS** pour l'automatisation!

---

## 🏢 5. Votre infrastructure complète

### Vue d'ensemble de votre architecture DNS

```
┌─────────────────────────────────────────────────────────────┐
│                    . (Racine Internet)                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                      .quebec (TLD)                          │
│  Géré par: Registre .quebec                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   sante.quebec                              │
│  Géré par: Ministère de la Santé                           │
│  Serveurs NS: ???                                           │
└─────────────────────────────────────────────────────────────┘
                            ↓ Délégation NS
┌─────────────────────────────────────────────────────────────┐
│                 aws.sante.quebec                            │
│  Géré par: Équipe AWS du ministère                         │
│  Zone Route53: Z08708363K93H1NMRIFRZ                       │
│  Serveurs NS: ns-354.awsdns-42.com (exemple)               │
│                                                             │
│  Records:                                                   │
│  ├─ aws.sante.quebec → A → 10.x.x.x                       │
│  ├─ www.aws.sante.quebec → CNAME → aws.sante.quebec       │
│  └─ netbox.aws.sante.quebec → NS → (délégation)           │
│       ├─ ns-1600.awsdns-08.co.uk                          │
│       ├─ ns-638.awsdns-15.net                             │
│       ├─ ns-84.awsdns-10.com                              │
│       └─ ns-1433.awsdns-51.org                            │
└─────────────────────────────────────────────────────────────┘
                            ↓ Délégation NS
┌─────────────────────────────────────────────────────────────┐
│            netbox.aws.sante.quebec                          │
│  Géré par: Équipe Netbox                                   │
│  Zone Route53: Z0811627115HEYTKBQUFW (publique)           │
│  Serveurs NS: ns-1600.awsdns-08.co.uk, etc.               │
│                                                             │
│  Records:                                                   │
│  ├─ prod.netbox.aws.sante.quebec                          │
│  │   └─ Certificat ACM validation:                        │
│  │       _87409773...prod.netbox → CNAME → ...acm-val...  │
│  │                                                         │
│  └─ test.netbox.aws.sante.quebec                          │
│      └─ Certificat ACM validation:                        │
│          _fbeb2d54...test.netbox → CNAME → ...acm-val...  │
└─────────────────────────────────────────────────────────────┘
```

---

### Scénario complet: Accéder à `prod.netbox.aws.sante.quebec`

Imaginons que vous avez un ALB (Application Load Balancer) avec le certificat SSL pour `prod.netbox.aws.sante.quebec`.

#### Configuration complète:

**1. Record A dans Route53:**
```
prod.netbox.aws.sante.quebec → A → 10.168.1.100
```
Ou mieux, un alias vers l'ALB:
```
prod.netbox.aws.sante.quebec → ALIAS → my-alb-123.ca-central-1.elb.amazonaws.com
```

**2. Certificat ACM:**
```
Domaine: prod.netbox.aws.sante.quebec
Status: ISSUED
ARN: arn:aws:acm:ca-central-1:212822971002:certificate/7d912cf7-...
```

**3. Record de validation (doit rester):**
```
_87409773503dc25331643efae3f95496.prod.netbox.aws.sante.quebec
  → CNAME →
_95341ec0860a537b3d7b436362363cb8.jkddzztszm.acm-validations.aws
```

**4. Délégation NS (dans aws.sante.quebec):**
```
netbox.aws.sante.quebec → NS →
  - ns-1600.awsdns-08.co.uk
  - ns-638.awsdns-15.net
  - ns-84.awsdns-10.com
  - ns-1433.awsdns-51.org
```

---

#### Flux complet quand un utilisateur visite `https://prod.netbox.aws.sante.quebec`:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Utilisateur tape: https://prod.netbox.aws.sante.quebec  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Résolution DNS                                           │
│    - Serveur racine → .quebec                              │
│    - .quebec → sante.quebec                                │
│    - sante.quebec → aws.sante.quebec                       │
│    - aws.sante.quebec → "Pour netbox, demandez à ns-1600" │
│    - ns-1600 → "prod.netbox = 10.168.1.100"               │
│    ✅ IP obtenue: 10.168.1.100                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Connexion HTTPS                                          │
│    - Navigateur se connecte à 10.168.1.100:443            │
│    - Demande le certificat SSL                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. ALB présente le certificat                              │
│    - Certificat pour: prod.netbox.aws.sante.quebec        │
│    - Émis par: Amazon (ACM)                                │
│    - Valide jusqu'à: 2027-05-24                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Navigateur vérifie le certificat                        │
│    - ✅ Le nom correspond: prod.netbox.aws.sante.quebec    │
│    - ✅ Émis par une CA de confiance (Amazon)             │
│    - ✅ Pas expiré                                         │
│    - ✅ Signature valide                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Connexion sécurisée établie                             │
│    - 🔒 Cadenas vert dans le navigateur                    │
│    - Trafic chiffré avec TLS 1.3                          │
│    - L'utilisateur voit votre application!                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 Récapitulatif des types de records

| Type | Pointe vers | Usage principal | Votre exemple |
|------|-------------|-----------------|---------------|
| **A** | IPv4 | Site web, serveur | `prod.netbox → 10.168.1.100` |
| **AAAA** | IPv6 | Site web (IPv6) | `prod.netbox → 2001:db8::1` |
| **CNAME** | Autre nom | Alias, validation SSL | `_87409...prod.netbox → ...acm-val...` |
| **NS** | Serveurs DNS | Délégation de zone | `netbox → ns-1600.awsdns...` |
| **TXT** | Texte | Vérification, SPF, DKIM | `aws.sante.quebec → "v=spf1..."` |
| **MX** | Serveur mail | Email | `aws.sante.quebec → mail.sante.quebec` |
| **SOA** | Info zone | Métadonnées DNS | Automatique dans Route53 |

---

## ✅ Checklist finale pour votre infrastructure

### Pour que `prod.netbox.aws.sante.quebec` fonctionne:

- [x] **Zone Route53 créée:** `netbox.aws.sante.quebec` (Z0811627115HEYTKBQUFW)
- [x] **Délégation NS:** Dans `aws.sante.quebec`, records NS pointant vers les serveurs de la zone netbox
- [x] **Certificat ACM:** Créé pour `prod.netbox.aws.sante.quebec`
- [x] **Record CNAME de validation:** `_87409773...prod.netbox → ...acm-validations.aws`
- [ ] **Record A ou ALIAS:** `prod.netbox.aws.sante.quebec → IP ou ALB` (à créer quand vous déployez)
- [ ] **ALB/CloudFront:** Configuré avec le certificat ACM (à faire)

---

## 🎓 Points clés à retenir

1. **DNS = Annuaire téléphonique d'Internet**
   - Traduit les noms en adresses IP

2. **Délégation = Diviser pour mieux régner**
   - Permet à différentes équipes de gérer leurs sous-domaines

3. **CNAME = Alias**
   - Redirige un nom vers un autre nom

4. **NS = Panneau indicateur**
   - Dit où trouver les informations sur un sous-domaine

5. **Certificat SSL = Passeport du site web**
   - Prouve l'identité et chiffre les communications

6. **Validation DNS = Preuve de propriété**
   - Le record CNAME prouve que vous contrôlez le domaine

---

## 📚 Ressources supplémentaires

- [Documentation AWS Route53](https://docs.aws.amazon.com/route53/)
- [Documentation AWS Certificate Manager](https://docs.aws.amazon.com/acm/)
- [RFC 1034 - Domain Names - Concepts and Facilities](https://www.rfc-editor.org/rfc/rfc1034)
- [RFC 1035 - Domain Names - Implementation and Specification](https://www.rfc-editor.org/rfc/rfc1035)

---

**Document créé le:** 2026-04-25  
**Dernière mise à jour:** 2026-04-25  
**Auteur:** Équipe Infrastructure Netbox
