# =============================================================================
# Secrets Manager - Secret applicatif NetBox
# =============================================================================
#
# Le module netbox_app crée deux SecretProviderClass :
# 1. netbox-rds-spc → credentials DB (depuis le secret RDS auto-géré)
# 2. netbox-app-spc → secrets applicatifs (depuis le secret ci-dessous)
#
# Ce fichier crée le secret applicatif et le ConfigMap via app_config.
# =============================================================================

resource "random_password" "netbox_secret_key" {
  length  = 50
  special = false
}

resource "random_password" "superuser_password" {
  length  = 24
  special = false
}

resource "random_password" "superuser_api_token" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "netbox_app" {
  name                    = "netbox-app-secret"
  recovery_window_in_days = 7
  kms_key_id              = module.keyForNetbox.key_arn

  tags = {
    Name       = "netbox-app-secret"
    Compliance = "CCCS-Medium"
  }
}

resource "aws_secretsmanager_secret_version" "netbox_app" {
  secret_id = aws_secretsmanager_secret.netbox_app.id
  secret_string = jsonencode({
    secret_key          = random_password.netbox_secret_key.result
    superuser_password  = random_password.superuser_password.result
    superuser_api_token = random_password.superuser_api_token.result
  })
}

# =============================================================================
# ConfigMap uniquement (le SPC est créé par le module netbox_app)
# =============================================================================

resource "kubernetes_config_map" "netbox_config" {
  count = var.deploy_phase_2 ? 1 : 0
  metadata {
    name      = "netbox-config"
    namespace = var.netbox_namespace
  }

  data = local.netbox_configmap_data

  depends_on = [kubernetes_namespace.netbox]
}
