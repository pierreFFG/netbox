locals {
  # Active la validation DNS ACM uniquement si acm_validation_hosted_zone_id ressemble a un vrai ID Route53 (ex: ZXXXXXXXXXXXX).
  enable_acm_dns_validation = length(regexall("^Z[A-Z0-9]+$", var.acm_validation_hosted_zone_id)) > 0

  acm_dns_validation_records = local.enable_acm_dns_validation ? flatten([
    for cert_key, records in module.certificat_netbox.dns_validation_records : [
      for idx, record in records : {
        cert_key     = cert_key
        record_key   = "${cert_key}-${idx}"
        record_name  = record.name
        record_type  = record.type
        record_value = record.value
      }
    ]
  ]) : []

  acm_dns_validation_records_map = {
    for r in local.acm_dns_validation_records : r.record_key => r
  }
}

resource "aws_route53_record" "acm_dns_validation" {
  provider = aws.network
  for_each = local.acm_dns_validation_records_map

  zone_id         = var.acm_validation_hosted_zone_id
  name            = each.value.record_name
  type            = each.value.record_type
  ttl             = 60
  records         = [each.value.record_value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "netbox" {
  for_each = local.enable_acm_dns_validation ? module.certificat_netbox.certificate_arns : {}

  certificate_arn = each.value
  validation_record_fqdns = [
    for r in local.acm_dns_validation_records :
    aws_route53_record.acm_dns_validation[r.record_key].fqdn if r.cert_key == each.key
  ]
}
