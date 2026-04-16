# =============================================================================
# Outputs
# =============================================================================

# RDS
output "rds_endpoint" {
  description = "Endpoint de l'instance RDS PostgreSQL"
  value       = module.rds.rds_endpoint
  sensitive   = true
}

output "rds_secret_arn" {
  description = "ARN du secret master RDS (géré par AWS)"
  value       = module.rds.rds_secret_arn
  sensitive   = true
}

# Redis
output "redis_endpoint" {
  description = "Endpoint principal du cluster Redis"
  value       = module.redis_netbox.redis_endpoint
}

output "redis_port" {
  description = "Port du cluster Redis"
  value       = module.redis_netbox.redis_port
}

output "redis_secret_arn" {
  description = "ARN du secret Redis dans Secrets Manager"
  value       = module.redis_netbox.secrets_manager_secret_arn
}

# S3
output "s3_media_bucket" {
  description = "Nom du bucket S3 pour les médias NetBox"
  value       = module.s3_netbox_media.bucket
}

# Certificats
output "certificate_arns" {
  description = "ARNs des certificats ACM"
  value       = module.certificat_netbox.certificate_arns
}

output "dns_validation_records" {
  description = "Enregistrements CNAME pour la validation DNS des certificats"
  value       = module.certificat_netbox.dns_validation_records
}

# Secrets
output "netbox_app_secret_arn" {
  description = "ARN du secret applicatif NetBox dans Secrets Manager"
  value       = aws_secretsmanager_secret.netbox_app.arn
}

# URL d'accès
output "netbox_url" {
  description = "URL d'accès à NetBox"
  value       = "https://netbox.${var.palier}.${var.domain_zone}"
}

# CCCS Compliance
output "cloudtrail_arn" {
  description = "ARN du CloudTrail NetBox"
  value       = aws_cloudtrail.netbox.arn
}

output "alb_logs_bucket" {
  description = "Bucket S3 pour les logs ALB"
  value       = module.s3_alb_logs.bucket
}

output "cloudtrail_bucket" {
  description = "Bucket S3 pour CloudTrail"
  value       = module.s3_cloudtrail.bucket
}
