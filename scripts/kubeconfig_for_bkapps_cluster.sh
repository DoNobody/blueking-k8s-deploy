#!/bin/bash

secret=$(kubectl describe serviceaccounts bk-paas-engine | awk '/Mountable secrets/ { print $NF}')
token=$(kubectl get secret "$secret" -o go-template='{{.data.token | base64decode}}' && echo)
cadata=$(kubectl get secret "$secret" -o go-template='{{index .data "ca.crt"}}')
server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

if [[ "$server" =~ bcs.local ]]; then
    domain=$(echo "$server" | awk -F'[:/]' '{ print $4}')
    ip=$(getent hosts "$domain" | awk '{print $1}')
    server=$(sed "s/$domain/$ip/" <<<"$server")
fi

cat <<EOF
apiVersion: v1
kind: Config
users:
- name: bkapps
  user:
    token: "$token"
clusters:
- cluster:
    certificate-authority-data: "$cadata"
    server: "$server"
  name: bkapps
contexts:
- context:
    cluster: bkapps
    user: bkapps
  name: bkapps
current-context: bkapps

EOF
