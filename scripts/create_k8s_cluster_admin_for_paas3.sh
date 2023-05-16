#!/bin/bash

SELF_DIR=$(dirname "$(readlink -f "$0")")
NAMESPACE=${NAMESPACE:-blueking}
context="$1"
if [[ -z $context ]]; then
    context=$(kubectl config current-context)
fi

KUBECTL="kubectl --context=$context --namespace $NAMESPACE"
if ! kubectl get ns $NAMESPACE &>/dev/null; then
    kubectl create ns "$NAMESPACE"
fi

if ! $KUBECTL get sa -n "$NAMESPACE" | grep -q bk-paasengine; then
    $KUBECTL create -n "$NAMESPACE" serviceaccount bk-paasengine >&2
    $KUBECTL create clusterrolebinding bk-paasengine --clusterrole=cluster-admin --serviceaccount=${NAMESPACE}:bk-paasengine >&2
fi

secret=$($KUBECTL -n "$NAMESPACE" get serviceaccount bk-paasengine -o jsonpath='{range .secrets[*]}{.name}{"\n"}{end}' | grep bk-paasengine-token)
token=$($KUBECTL -n "$NAMESPACE" get secret "$secret" -o go-template='{{.data.token | base64decode}}' && echo)
cadata=$($KUBECTL -n "$NAMESPACE" get secret "$secret" -o go-template='{{index .data "ca.crt"}}')
server=$($KUBECTL config view --minify -o jsonpath='{.clusters[0].cluster.server}')

#if [[ "$server" =~ bcs.local ]]; then
#    domain=$(echo "$server" | awk -F'[:/]' '{ print $4}')
#    ip=$(getent hosts "$domain" | awk '{print $1}')
#    server=$(sed "s/$domain/$ip/" <<<"$server")
#fi

# 生成helmfile安装paasv3需要的k8s初始集群values格式：
# 请注意：这里默认paas3的应用k8s集群使用它自身部署相同的集群。如果使用不同的集群，请部署paas3后，根据管理页面提示配置。
cat <<EOF | tee "${SELF_DIR}"/../environments/default/paas3_initial_cluster.yaml
enabled: true
apiServers:
- url: "https://kubernetes.default.svc.cluster.local"
caData: "$cadata"
tokenValue: "$token"
EOF
