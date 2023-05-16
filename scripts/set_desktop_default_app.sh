#!/bin/bash

PROGRAM=$(basename "$0")
SELF_DIR=$(dirname "$(readlink -f "$0")")
bkValuesPath=${bkValuesPath:-"${SELF_DIR}/../environments/default"}

usage() {
    cat <<EOF
bkpaas3 桌面默认应用配置（仅对新用户有效）
用法: 
	$PROGRAM [ -a, --add 新增默认应用 使用,分割多个应用]
			 [ -d, --del 移除默认应用，使用,分割多个应用]
示例: 
$PROGRAM -a bk_nodeman,bk_bcs
EOF
}

usage_and_exit() {
    usage
    exit "$1"
}

(($# == 0)) && usage_and_exit 1
while (($# > 0)); do
    case "$1" in
    -a | --app)
        shift
        code_list="$1"
        flag="True"
        ;;
    -d | --del)
        shift
        code_list="$1"
        flag="False"
        ;;
    -h | --help | '-?')
        usage_and_exit 0
        ;;
    -*)
        error "不可识别的参数: $1"
        ;;
    *)
        break
        ;;
    esac
    shift $(($# == 0 ? 0 : 1))
done

if [[ -e ${bkValuesPath}/custom.yaml ]]; then
    # shellcheck disable=SC2016
    MERGED_VALUE=$(yq ea '. as $item ireduce ({}; . * $item)' "${bkValuesPath}"/{values,custom}.yaml)
else
    MERGED_VALUE=$(<"${bkValuesPath}"/values.yaml)
fi
read -r NAMESPACE < <(echo "$MERGED_VALUE" | yq e '.namespace' -)

deploy="deploy/bk-console-web"
kubectl -n "$NAMESPACE" exec -i "$deploy" -- bash -c "export BK_ENV='env';export flag=${flag};export code_list=${code_list};python manage.py shell" <<EOF
from app.models import App
from os import getenv
code_list=getenv('code_list').split(',')
flag=getenv('flag')
if flag:
	App.objects.filter(code__in=code_list).update(is_default=True)
else:
	App.objects.filter(code__in=code_list).update(is_default=False)
EOF
