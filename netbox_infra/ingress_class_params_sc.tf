resource "kubectl_manifest" "ingress_class_params" {
  yaml_body = templatefile("${path.module}/k8s_common_res/ingress_class_params.yaml.tpl", {
    ingress_class_name = var.ingress_class_name
    scheme             = var.scheme
  })
}

resource "kubectl_manifest" "ingress_class" {
  depends_on = [kubectl_manifest.ingress_class_params]

  yaml_body = templatefile("${path.module}/k8s_common_res/ingress_class.yaml.tpl", {
    ingress_class_name = var.ingress_class_name
  })
}
