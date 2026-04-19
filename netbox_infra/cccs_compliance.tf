# =============================================================================
# CCCS-Medium Compliance Resources
# Conformité CCCS-Medium : Logging, Audit, Monitoring
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Groups pour Redis (CCCS: Audit Logging)
# Note: La rétention est gérée par la LZA.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name = "/aws/elasticache/${var.redis_cluster_name}/slow-log"

  tags = {
    Name       = "${var.redis_cluster_name}-slow-log"
    Compliance = "CCCS-Medium"
  }
}

resource "aws_cloudwatch_log_group" "redis_engine_log" {
  name = "/aws/elasticache/${var.redis_cluster_name}/engine-log"

  tags = {
    Name       = "${var.redis_cluster_name}-engine-log"
    Compliance = "CCCS-Medium"
  }
}

# -----------------------------------------------------------------------------
# S3 CloudTrail (via module S3)
# -----------------------------------------------------------------------------

module "s3_cloudtrail" {
  source                      = "git::https://dev.azure.com/RSSS-CEI-C/Escouade%20Voie%20Libre/_git/SanteQuebec.Terraform.Modules//s3?ref=master"
  account_id                  = local.account_id
  identifiant                 = "netbox00-cloudtrail-${local.account_id}"
  cle_chiffrement_externe     = true
  arn_cle_chiffrement         = module.keyForNetbox.key_arn
  activer_versionnage         = true
  activer_verrouillage_objets = false

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::netbox00-cloudtrail-${local.account_id}"
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::netbox00-cloudtrail-${local.account_id}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudTrail (CCCS-Requirement: Audit Logging)
# -----------------------------------------------------------------------------

resource "aws_cloudtrail" "netbox" {
  name                       = "netbox00-trail"
  s3_bucket_name             = module.s3_cloudtrail.id
  is_multi_region_trail      = true
  enable_log_file_validation = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = {
    Name       = "netbox00-trail"
    Compliance = "CCCS-Medium"
  }

  depends_on = [module.s3_cloudtrail]
}

# -----------------------------------------------------------------------------
# ALB Access Logs
# Les logs ALB sont centralises dans un bucket S3 du compte LogArchive.
# Le bucket/prefix sont fournis par variables (pas de creation locale ici).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CloudWatch Alarms (CCCS: Monitoring)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "netbox-rds-high-cpu"
  alarm_description   = "Alerte quand le CPU RDS dépasse 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = var.rds_identifier
  }

  tags = { Compliance = "CCCS-Medium" }
}

resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "netbox-rds-low-storage"
  alarm_description   = "Alerte quand le stockage RDS libre est sous 5 Go"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5 Go en bytes

  dimensions = {
    DBInstanceIdentifier = var.rds_identifier
  }

  tags = { Compliance = "CCCS-Medium" }
}

resource "aws_cloudwatch_metric_alarm" "redis_high_cpu" {
  alarm_name          = "netbox-redis-high-cpu"
  alarm_description   = "Alerte quand le CPU Redis dépasse 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ReplicationGroupId = var.redis_cluster_name
  }

  tags = { Compliance = "CCCS-Medium" }
}
