#!/bin/bash

SELF_DIR=$(readlink -f $(dirname $0))
APP_SECRET_CONF="$1"
APP_CODES=( bk_repo bk_paas bk_iam bk_ssm bk_apigateway bk_apigw_test bk_cmdb bk_job bk_gse bk_paas3 bk_usermgr bk_ci bk_monitorv3 bk_bkdata bk_log_search bk_bcs_app bk_codecc bk_nodeman)

if ! command -v yq &>/dev/null; then
    echo "未安装 yq 命令。"
    exit 1
fi

if ! command -v uuid &>/dev/null; then
    echo "未安装 uuid 命令。"
    echo "尝试自动安装 uuid 命令"
    if ! yum -y install uuid; then
       echo "安装uuid命令失败"
       exit 1
    fi
fi

if [[ -z "$APP_SECRET_CONF" ]]; then
    echo "Usage: $0 <app_secret_file_path>"
    exit 1
fi
declare -A SECRETS
# 如果配置已经存在，先读入复用
if [[ -f "$APP_SECRET_CONF" ]]; then
    while read app_code app_secret; do
        SECRETS[$app_code]=$app_secret
    done < <(yq e -o tsv  '.appSecret | to_entries | .[] | [.key, .value]'  "$APP_SECRET_CONF")
fi

echo "# app_code对应的app_secret值" | tee "$APP_SECRET_CONF"
echo "appSecret:" | tee -a "$APP_SECRET_CONF"
for code in "${APP_CODES[@]}" ; do
    if [[ -n ${SECRETS[$code]} ]]; then
        secret=${SECRETS[$code]}
    else
        echo "## $code is new app_code, generate a new secret" >&2
        secret=$(uuid -v4)
    fi
    printf "  %s: %s\n" "$code" "$secret" | tee -a "$APP_SECRET_CONF"
done

