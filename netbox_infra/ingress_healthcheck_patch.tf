resource "kubectl_manifest" "netbox_ingress_healthcheck_patch" {
  count = var.deploy_phase_2 ? 1 : 0

  yaml_body = <<-YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-netbox
  namespace: ${var.netbox_namespace}
  annotations:
    alb.ingress.kubernetes.io/group.name: ${var.palier}-netbox
    alb.ingress.kubernetes.io/healthcheck-path: /static/netbox.css
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/load-balancer-attributes: "access_logs.s3.enabled=true,access_logs.s3.bucket=${var.alb_logs_bucket_name},access_logs.s3.prefix=${var.alb_logs_prefix},deletion_protection.enabled=true,routing.http.drop_invalid_header_fields.enabled=true"
    alb.ingress.kubernetes.io/success-codes: "200"
    alb.ingress.kubernetes.io/target-type: ip
    external-dns.alpha.kubernetes.io/hostname: ${var.netbox_fqdn}.
spec:
  ingressClassName: ${var.ingress_class_name}
  rules:
    - host: ${var.netbox_fqdn}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-netbox
                port:
                  number: 80
YAML

  depends_on = [module.netbox_app]
}
