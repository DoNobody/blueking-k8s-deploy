#! /bin/bash

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: "$1"
  labels:
     bcs-webhook: "false"
EOF