#!/usr/bin/env bash

GATEWAY_TOKEN=$(kubectl get secret --namespace bcs-system bcs-password -o jsonpath="{.data.gateway_token}" | base64 -d)

if [[ -z "$GATEWAY_TOKEN" ]]; then
    echo "获取bcs的gateway token失败"
    exit 1
fi

if ! [[ -f ./environments/default/bkmonitor-custom-values.yaml.gotmpl ]]; then
  cat > ./environments/default/bkmonitor-custom-values.yaml.gotmpl <<EOF
monitor:
  config:
    bcsApiGatewayToken: "$GATEWAY_TOKEN"
EOF
fi

if ! [[ -f ./environments/default/bklog-search-custom-values.yaml.gotmpl ]]; then
cat > ./environments/default/bklog-search-custom-values.yaml.gotmpl <<EOF
configs:
  bcsApiGatewayToken: "$GATEWAY_TOKEN"
EOF
fi
