resource "kubectl_manifest" "netbox_extra_py_s3_config" {
  count = var.deploy_phase_2 ? 1 : 0

  yaml_body = <<-YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: netbox-extra-config
  namespace: ${var.netbox_namespace}
data:
  extra.py: |
    STORAGE_BACKEND = "storages.backends.s3boto3.S3Boto3Storage"
    STORAGE_CONFIG = {
        "AWS_STORAGE_BUCKET_NAME": "${module.s3_netbox_media.bucket}",
        "AWS_S3_REGION_NAME": "${var.region}",
        "AWS_S3_ADDRESSING_STYLE": "virtual",
        "AWS_DEFAULT_ACL": None,
    }
YAML
}
