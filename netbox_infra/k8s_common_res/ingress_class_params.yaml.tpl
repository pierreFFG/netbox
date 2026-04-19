apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: ${ingress_class_name}
spec:
  scheme: ${scheme}
