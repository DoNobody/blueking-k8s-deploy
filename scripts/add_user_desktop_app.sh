#! /bin/bash

PROGRAM=$(basename "$0")
SELF_DIR=$(dirname "$(readlink -f "$0")")
bkValuesPath=${bkValuesPath:-"${SELF_DIR}/../environments/default"}

usage() {
    cat <<EOF
bkpaas 用户桌面上添加应用
用法: 
    $PROGRAM [-u, --user 用户列表 使用,分割多个用户]
            [ -a, --app 应用列表 使用,分割多个应用]
示例: 
$PROGRAM -u admin,test -a bk_nodeman,bk_bcs
EOF
}

usage_and_exit() {
    usage
    exit "$1"
}

(($# == 0)) && usage_and_exit 1
while (($# > 0)); do
    case "$1" in
    -u | --user)
        shift
        user_list=$1
        ;;
    -a | --app)
        shift
        code_list="$1"
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
# k8s env variable
read -r NAMESPACE < <(echo "$MERGED_VALUE" | yq e '.namespace' -)
deploy="deploy/bk-console-web"

IFS=','
read -ra users <<<"$user_list"
read -ra apps <<<"$code_list"

for user in "${users[@]}"; do
    for app in "${apps[@]}"; do
        kubectl -n "$NAMESPACE" exec -i "$deploy" -- python manage.py add_app_to_desktop --app_code="$app" --username="$user"
    done
done
