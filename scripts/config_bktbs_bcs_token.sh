#!/usr/bin/env bash

GATEWAY_TOKEN=$(kubectl get secret --namespace bcs-system bcs-password -o jsonpath="{.data.gateway_token}" | base64 -d)

if [[ -z "$GATEWAY_TOKEN" ]]; then
    echo "获取bcs的gateway token失败"
    exit 1
fi

cat > ./environments/default/bkci/bktbs-custom-values.yaml.gotmpl <<EOF
server:
  bcs:
    # bcs请求token
    apiToken: "$GATEWAY_TOKEN"
EOF
