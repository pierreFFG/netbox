# =============================================================================
# Kubernetes Resources - Déploiement NetBox via module netbox_app
# =============================================================================

# =============================================================================
# NetBox App (web + worker + service + ingress)
# =============================================================================

module "netbox_app" {
  count  = var.deploy_phase_2 ? 1 : 0
  source = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//k8s_config_apps//netbox_app?ref=master"

  namespace            = var.netbox_namespace
  service_account_name = "netbox-sa"
  name                 = "deployment-netbox"
  app_label            = "netbox"
  image_tag            = var.netbox_image_tag
  repository_name      = "netbox-image"
  account_id           = var.account_id
  container_name       = "netbox"
  container_port       = 8080
  replicas             = var.netbox_replicas
  configmap_name       = "netbox-config"
  extra_configmap_name = "netbox-extra-config"

  # Resources (CCCS: dimensionné pour >1000 devices)
  resources = {
    requests = { cpu = "250m", memory = "512Mi" }
    limits   = { cpu = "500m", memory = "1Gi" }
  }

  # Probes
  readiness_probe_path          = "/api/"
  liveness_probe_path           = "/api/"
  readiness_probe_initial_delay = 120
  liveness_probe_initial_delay  = 300
  readiness_probe_use_tcp       = true
  liveness_probe_use_tcp        = true

  # Service
  service_config = {
    service_name = "service-netbox"
    port         = 80
    target_type  = "ip"
  }

  # Secrets - deux SPC : DB creds + secrets applicatifs
  secret_providers = [
    {
      spc_name   = "netbox-rds-spc"
      secret_arn = module.rds.rds_secret_arn
      jmes_paths = [
        { path = "username", object_alias = "DB_USER" },
        { path = "password", object_alias = "DB_PASSWORD" }
      ]
    },
    {
      spc_name   = "netbox-app-spc"
      secret_arn = aws_secretsmanager_secret.netbox_app.arn
      jmes_paths = [
        { path = "secret_key", object_alias = "SECRET_KEY" },
        { path = "superuser_password", object_alias = "SUPERUSER_PASSWORD" },
        { path = "superuser_api_token", object_alias = "SUPERUSER_API_TOKEN" }
      ]
    }
  ]

  # Env vars injectés depuis les K8s secrets créés par les SPC
  env_from_secrets = [
    { spc_name = "netbox-rds-spc", object_alias = "DB_USER" },
    { spc_name = "netbox-rds-spc", object_alias = "DB_PASSWORD" },
    { spc_name = "netbox-app-spc", object_alias = "SECRET_KEY" },
    { spc_name = "netbox-app-spc", object_alias = "SUPERUSER_PASSWORD" },
    { spc_name = "netbox-app-spc", object_alias = "SUPERUSER_API_TOKEN" }
  ]

  # Env vars statiques
  extra_env = {
    SUPERUSER_NAME  = "admin"
    SUPERUSER_EMAIL = "admin@sante.quebec"
    SKIP_SUPERUSER  = "true"
    HOME            = "/tmp"
    PGSSLMODE       = "require"
    REDIS_PASSWORD  = module.redis_netbox.auth_token
    REDIS_SSL       = "true"
  }

  # Ingress ALB (CCCS: HTTPS, access logs, deletion protection)
  enable_ingress        = true
  ingress_class_name    = var.ingress_class_name
  ingress_name          = "ingress-netbox"
  ingress_path          = "/"
  service_name          = "service-netbox"
  service_port          = 80
  target_type           = "ip"
  alb_group_name        = "${var.palier}-netbox"
  external_dns_hostname = "${var.netbox_fqdn}."
  hosts                 = [var.netbox_fqdn]
  listen_ports          = [{ "HTTP" = 80 }, { "HTTPS" = 443 }]
  certificate_arns      = [module.certificat_netbox.certificate_arns["netbox"]]
  alb_extra_attributes  = "access_logs.s3.enabled=true,access_logs.s3.bucket=${var.alb_logs_bucket_name},access_logs.s3.prefix=${var.alb_logs_prefix},deletion_protection.enabled=true,routing.http.drop_invalid_header_fields.enabled=true"

  # Topology (CCCS: haute disponibilité multi-AZ)
  topology_spread_min_domains        = 2
  topology_spread_when_unsatisfiable = "DoNotSchedule"

  # Worker (rqworker)
  enable_worker   = true
  worker_replicas = 1
  worker_command  = ["python", "/opt/netbox/netbox/manage.py", "rqworker"]
  worker_resources = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "250m", memory = "512Mi" }
  }

  depends_on = [
    module.eks_config,
    kubectl_manifest.ingress_class,
    module.rds,
    module.redis_netbox,
    module.certificat_netbox,
    kubernetes_config_map_v1.netbox_config,
    aws_secretsmanager_secret_version.netbox_app
  ]
}