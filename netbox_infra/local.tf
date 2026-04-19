locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  domain_zone = var.domain_zone

  registre_ecr = "${var.account_id}.dkr.ecr.ca-central-1.amazonaws.com"

  # Extraire le host depuis rds_endpoint (format "host:port")
  rds_host = split(":", module.rds.rds_endpoint)[0]

  # Pod Identity pour NetBox
  # Le web et le worker partagent le même service account (netbox-sa)
  # Un seul pod identity suffit
  pod_identities = {
    netbox = {
      app_name               = "netbox"
      pod_namespace          = var.netbox_namespace
      pod_permissions_policy = local.netbox_pod_permissions_policy
      managed_policies       = []
    }
  }

  netbox_pod_permissions_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:netbox-*",
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:rds!*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [
          module.keyForNetbox.key_arn,
          module.rds.kms_key_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_netbox_media.arn,
          "${module.s3_netbox_media.arn}/*"
        ]
      }
    ]
  })

  # Configuration du ConfigMap NetBox (variables non-sensibles)
  netbox_configmap_data = {
    DB_HOST       = local.rds_host
    DB_PORT       = "5432"
    DB_NAME       = var.rds_db_name
    DB_SSLMODE    = "require"
    REDIS_HOST    = module.redis_netbox.redis_endpoint
    REDIS_PORT    = "6379"
    ALLOWED_HOSTS = "*"
    TIME_ZONE     = "America/Toronto"
  }
}
