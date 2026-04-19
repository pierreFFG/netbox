module "eks_addons" {
  count  = var.deploy_phase_2 ? 1 : 0
  source = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//eks_addons?ref=master"

  cluster_name    = var.cluster_name
  region          = var.region
  cluster_oidc_id = var.cluster_oidc_id

  addons = [
    # secrets-store-csi-driver
    {
      name        = "secrets-store-csi-driver"
      namespace   = "kube-system"
      chart       = "secrets-store-csi-driver"
      repo        = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
      version     = "1.4.0"
      local_chart = null

      set_values = {
        "linux.priorityClassName"             = "system-node-critical"
        "linux.providerImage"                 = "${local.registre_ecr}/ecr-public/aws-secrets-manager/secrets-store-csi-driver-provider-aws:1.0.r2-96-gfeeb3ac-2025.05.06.20.19"
        "linux.image.repository"              = "${local.registre_ecr}/kubernetes/csi-secrets-store/driver"
        "linux.image.tag"                     = "v1.4.8"
        "linux.crds.image.repository"         = "${local.registre_ecr}/kubernetes/csi-secrets-store/driver-crds"
        "linux.crds.image.tag"                = "v1.5.1"
        "linux.registrarImage.repository"     = "${local.registre_ecr}/kubernetes/sig-storage/csi-node-driver-registrar"
        "linux.registrarImage.tag"            = "v2.13.0"
        "linux.livenessProbeImage.repository" = "${local.registre_ecr}/kubernetes/sig-storage/livenessprobe"
        "linux.livenessProbeImage.tag"        = "v2.13.1"
        "syncSecret.enabled"                  = "true"
        "enableSecretRotation"                = "true"
        "logVerbosity"                        = "2"
      }
    },
    # secrets-store-csi-provider-aws
    {
      name        = "secrets-store-csi-provider-aws"
      namespace   = "kube-system"
      chart       = "secrets-store-csi-driver-provider-aws"
      repo        = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
      version     = "1.0.1"
      local_chart = null

      set_values = {
        "image.repository" = "${local.registre_ecr}/ecr-public/aws-secrets-manager/secrets-store-csi-driver-provider-aws"
        "image.tag"        = "1.0.r2-96-gfeeb3ac-2025.05.06.20.19"
      }
    },
    # metrics-server
    {
      name        = "metrics-server"
      namespace   = "kube-system"
      chart       = "metrics-server"
      repo        = "https://kubernetes-sigs.github.io/metrics-server/"
      version     = "3.12.2"
      local_chart = null

      set_values = {
        "image.repository"              = "${local.registre_ecr}/kubernetes/metrics-server"
        "image.tag"                     = "v0.8.1"
        "addonResizer.image.repository" = "${local.registre_ecr}/kubernetes/metrics-server/addon-resizer"
        "addonResizer.image.tag"        = "1.8.21"
      }
    },
    # external-dns (gestion des enregistrements Route53 a partir des ingress)
    {
      name        = "external-dns"
      namespace   = "kube-system"
      chart       = "external-dns"
      repo        = "oci://registry-1.docker.io/bitnamicharts"
      version     = "8.8.4"
      local_chart = null

      values = [yamlencode({
        image = {
          registry   = local.registre_ecr
          repository = "bitnami/external-dns"
          tag        = "0.20.0"
        }
        serviceAccount = {
          create = true
          name   = "external-dns-sa"
          annotations = {
            "eks.amazonaws.com/role-arn" = "arn:aws:iam::${local.account_id}:role/external-dns-irsa"
          }
        }
        provider      = "aws"
        sources       = ["ingress"]
        registry      = "txt"
        txtOwnerId    = lower(var.environment)
        interval      = "1m"
        policy        = "upsert-only"
        logLevel      = "info"
        domainFilters = [var.domain_zone]
        zoneIdFilters = [var.hosted_zone_id]
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
        aws = {
          zoneType      = var.hosted_zone_type
          region        = var.region
          assumeRoleArn = var.external_dns_assume_role_arn
        }
        global = {
          security = {
            allowInsecureImages = true
          }
        }
      })]
      set_values = {}
    }
  ]

  irsa_roles = [
    {
      name            = "secrets-store-irsa"
      service_account = "secret-store-csi-sa"
      namespace       = "kube-system"
      policy_json = jsonencode({
        actions = [
          "secretsmanager:GetSecretValue",
          "ssm:GetParameters",
          "ssm:GetParameter",
          "kms:Decrypt"
        ],
        resources = ["*"]
      })
    },
    {
      name            = "external-dns-irsa"
      service_account = "external-dns-sa"
      namespace       = "kube-system"
      policy_json = jsonencode({
        actions = [
          "sts:AssumeRole"
        ],
        resources = [
          var.external_dns_assume_role_arn
        ]
      })
    }
  ]

  depends_on = [module.eks, module.eks_node[0]]
}
