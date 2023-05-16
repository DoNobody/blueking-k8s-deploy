#!/usr/bin/env bash

set -eo pipefail

# 定义已经存在的keypair配置文件路径
RSA_KEYPAIR_CONF="$1"
# 定义接入apigateway的网关名和app_code的映射
declare -A SYSTEM_CODES=(
  ["bk-iam"]=bk_iam
  ["bk-auth"]=bk_auth
  ["bk-user"]=bk_usermgr
  ["bk-gse"]=bk_gse
  ["bcs-api-gateway"]=bk_bcs_app
  ["bcs-app"]=bk_bcs_app
)

if ! command -v yq &>/dev/null; then
    echo "未安装 yq 命令。"
    exit 1
fi

if ! command -v openssl &>/dev/null; then
    echo "can't found openssl command"
    exit 1
fi

# 如果配置已经存在，先读入复用
declare -A PUB PRIV
if [[ -f "$RSA_KEYPAIR_CONF" ]]; then
    while read app_code priv pub; do
        PRIV[$app_code]="$priv"
        PUB[$app_code]="$pub"
    done < <(yq  e -o tsv  '.builtinGateway | to_entries | .[] | [.value.appCode,.value.privateKeyBase64,.value.publicKeyBase64]' "${RSA_KEYPAIR_CONF}")
fi

echo "# 网关内置的keypair信息" | tee "$RSA_KEYPAIR_CONF"
echo "builtinGateway:" | tee -a "$RSA_KEYPAIR_CONF"
for system in "${!SYSTEM_CODES[@]}"; do 
    app_code="${SYSTEM_CODES[$system]}"
    if [[ -n ${PRIV[$app_code]} ]]; then
        private_base64=${PRIV[$app_code]}
        public_base64=${PUB[$app_code]}
    else
        echo "## $system is new system, generate a new rsa key pair" >&2
        private=$(openssl genrsa 2048 2>/dev/null)
        private_base64=$(echo -n "$private" | base64 -w0)
        public=$(echo "$private" | openssl rsa -outform PEM -pubout 2>/dev/null)
        public_base64=$(echo -n "$public" | base64 -w0)
    fi
    {
    printf "  \042%s\042:\n" "$system"
    printf "    appCode: %s\n" "${app_code}"
    printf "    privateKeyBase64: %s\n" "${private_base64}"
    printf "    publicKeyBase64: %s\n" "${public_base64}"
    } | tee -a "$RSA_KEYPAIR_CONF"
done
