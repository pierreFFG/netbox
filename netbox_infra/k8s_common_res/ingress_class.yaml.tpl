apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: ${ingress_class_name}
spec:
  controller: eks.amazonaws.com/alb
  parameters:
    apiGroup: eks.amazonaws.com
    kind: IngressClassParams
    name: ${ingress_class_name}
