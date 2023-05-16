#!/bin/bash

# safe mode
set -euo pipefail

trap "on_ERR;" ERR
on_ERR() {
    local ret=$? cmd="$BASH_COMMAND" f="${BASH_SOURCE:--}" lino="${BASH_LINENO[0]}"
    printf >&2 "ERROR: %s:%s: \033[7m%s\033[0m exit with code %s.\n" "$f" "$lino" "$cmd" "$ret"
    exit "$ret"
}

# echo
TIME_STAMP="+%Y-%m-%d/%H:%M:%S"

highlight() {
    local level=INFO
    echo -e "$(date ${TIME_STAMP}) [${level}] \033[7m$*\033[0m"
}

error() {
    local level=ERROR
    echo -e "$(date ${TIME_STAMP}) [${level}] \033[31m$*\033[0m"
    exit 1
}

# common value
PROGRAM=$(basename "$0")
SELF_DIR=$(dirname "$(readlink -f "$0")")
OP_TYPE=
PROJECT=
OP_FLAG="true"
VERSION="7.0.0"

# PROJECTS
INSTALL_PROJECTS=(base nodeman bcs mointor log saas itsm sops gsekit lesscode)
SAAS_PROJECTS=(itsm sops gsekit lesscode)
HOST_PROJECTS=(blueking)
UPLOAD_PROJECTS=(runtime redis agent plugin)

# Path
bkHelmfilePath=${bkHelmfilePath:-${SELF_DIR}/../..}
bkToolPath=${bkToolPath:-"${bkHelmfilePath}/bin"}
bkSaaSPath=${bkSaaSPath:-"${bkHelmfilePath}/saas"}
bkGsePath=${bkGsePath:-"${bkHelmfilePath}/gse"}
bkAgentsPath=${bkAgentsPath:-${bkGsePath}/agents}
bkPluginsPath=${bkPluginsPath:-${bkGsePath}/plugins}
bkBluekingPath=${bkBluekingPath:-"${bkHelmfilePath}/blueking"}
bkValuesPath=${bkValuesPath:-"${bkBluekingPath}/environments/default"}
bkScriptsPath=${bkScriptsPath:-"${bkBluekingPath}/scripts"}

_bash_completion() {
    # 下载bash-completion
    if ! rpm -q bash-completion &>/dev/null; then
        sudo yum -y install bash-completion || highlight "yum install bash-completion Failed"
    fi
    if ! [[ -f /etc/bash_completion.d/$1 ]]; then
        if [[ $1 == helmfile ]]; then
            cat <<'EOF' | sudo tee /etc/bash_completion.d/"$1" >/dev/null 2>&1
#! /bin/bash

_helmfile_bash_autocomplete() {
  if [[ "${COMP_WORDS[0]}" != "source" ]]; then
    local cur opts base
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ "$cur" == "-"* ]]; then
      opts=$(${COMP_WORDS[@]:0:$COMP_CWORD} ${cur} --generate-bash-completion)
    else
      opts=$(${COMP_WORDS[@]:0:$COMP_CWORD} --generate-bash-completion)
    fi
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
  fi
}

complete -o bashdefault -o default -o nospace -F _helmfile_bash_autocomplete helmfile
EOF
            echo "add $1 auto bash completion"
        else
            $1 completion bash | sudo tee /etc/bash_completion.d/"$1" >/dev/null 2>&1
            echo "add $1 auto bash completion"
        fi
    fi
}

_install_tools() {
    # install yq helm helmfile kubectl
    if ! command -v helm >/dev/null; then
        if [[ -x ${bkToolPath}/helm ]]; then
            sudo cp -a "${bkToolPath}"/helm /usr/local/bin/ && sudo chmod +x /usr/local/bin/helm
        else
            error "${bkToolPath}/helm doesn't exsit"
        fi
    fi
    if ! command -v helmfile >/dev/null; then
        if [[ -x ${bkToolPath}/helmfile ]]; then
            sudo cp -a "${bkToolPath}"/helmfile /usr/local/bin/ && sudo chmod +x /usr/local/bin/helmfile
        else
            error "${bkToolPath}/helmfile doesn't exsit"
        fi
    fi

    if ! command -v yq >/dev/null; then
        if [[ -x ${bkToolPath}/helmfile ]]; then
            sudo cp -a "${bkToolPath}"/yq /usr/local/bin && sudo chmod +x /usr/local/bin/yq
        else
            error "${bkToolPath}/yq doesn't exsit"
        fi
    fi
    if ! [[ -x $HOME/.local/share/helm/plugins/helm-diff/bin/diff ]]; then
        tar xf "${bkToolPath}"/helm-plugin-diff.tgz -C "$HOME"/
    fi
    _bash_completion yq
    _bash_completion helm
    _bash_completion helmfile
    _bash_completion kubectl
    local MERGED_VALUE
    if [[ -e ${bkValuesPath}/custom.yaml ]]; then
        # shellcheck disable=SC2016
        MERGED_VALUE=$(yq ea '. as $item ireduce ({}; . * $item)' "${bkValuesPath}"/{values,custom}.yaml)
    else
        MERGED_VALUE=$(<"${bkValuesPath}"/values.yaml)
    fi
    read -r BK_DOMAIN NAMESPACE < <(echo "$MERGED_VALUE" | yq e '[.domain.bkDomain, .namespace] | @tsv' -)
    NAMESPACE=${NAMESPACE:-"blueking"}
    REGISTRY=${REGISTRY:-$(echo "$MERGED_VALUE" | yq e '.imageRegistry' -)}
    REPOSITORY=${REPOSITORY:-"https://hub.bktencent.com/chartrepo/blueking"}
}

_install_tools

# safe mod
usage_and_exit() {
    cat <<EOF
蓝鲸7.0.0灰度版本一键部署脚本，版本 $VERSION ，适合蓝鲸bcs脚本自建集群和minikube集群
$PROGRAM    [ -h --h --help -?  查看帮助 ]
            [ -i, --install     支持安装模块(${INSTALL_PROJECTS[*]}) ]
            [ 当安装(${SAAS_PROJECTS[*]})，后接@指明安装环境prod/stag，缺省为prod]
            [ -d, --domain      指定域名,默认从custom.yaml中读取，缺省值为${BK_DOMAIN}]
            [ -D, --DNS        列出需要配置的用户侧DNS，支持模块(${HOST_PROJECTS[*]})]
            [ -u, --upload     上传资源，支持模块(${UPLOAD_PROJECTS[*]})]
------------------------------------------------------
步骤1 安装蓝鲸基座
bash $PROGRAM --install base 
# 确保能解析bkrepo.${BK_DOMAIN}后再执行
bash $PROGRAM --install nodeman
# 显示需要配置的dns
bash $PROGRAM --DNS
------------------------------------------------------
步骤2 准备好SaaS运行环境，安装蓝鲸基础套餐saas应用至生产环境
# 若安装选项为saas，则itsm/sops/gsekit/lesscode一次性并行安装至生产环境
bash $PROGRAM --install saas 
# 安装单个应用至预发布环境
bash $PROGRAM --install itsm@stag
-------------------------------------------------------
步骤3 安装蓝鲸容器管理套餐
bash $PROGRAM --install bcs
------------------------------------------------------
步骤4 安装蓝鲸监控日志套餐
bash $PROGRAM --install monitor
bash $PROGRAM --install log
EOF
    exit "$1"
}

while (($# > 0)); do
    case "$1" in
    --install | -i)
        if ${OP_FLAG}; then
            shift
            PROJECT="$1"
            OP_TYPE="install"
            OP_FLAG="false"
            if [[ "${SAAS_PROJECTS[*]/${PROJECT%%@*}/}" != "${SAAS_PROJECTS[*]}" ]]; then
                case "${PROJECT##*@}" in
                prod | PROD)
                    SaaSEnv=prod
                    ;;
                stag | STAG)
                    SaaSEnv=stag
                    ;;
                *)
                    SaaSEnv=prod
                    ;;
                esac
                PROJECT="${PROJECT%%@*}"
            fi
        else
            usage_and_exit 1
        fi
        ;;
    -u | --upload)
        shift
        PROJECT="$1"
        if [[ ${PROJECT%%@*} == agent ]]; then
            case "${PROJECT##*@}" in
            prod | PROD)
                SaaSEnv=prod
                ;;
            stag | STAG)
                SaaSEnv=stag
                ;;
            *)
                SaaSEnv=prod
                ;;
            esac
            PROJECT="${PROJECT%%@*}"
        fi
        OP_TYPE='upload'
        OP_FLAG='false'
        ;;
    --DNS | --dns | -D)
        if ${OP_FLAG}; then
            shift
            PROJECT="$1"
            OP_TYPE='host'
            OP_FLAG="false"
        else
            usage_and_exit 1
        fi
        ;;
    --domain | -d)
        shift
        BK_DOMAIN="$1"
        ;;
    --help | -h | --h | '-?')
        usage_and_exit 0
        ;;
    -*)
        error "不可识别的参数: $1"
        ;;
    *)
        break
        ;;
    esac
    shift
done

# 检测kubectl环境
if ! command -v kubectl >/dev/null 2>&1; then
    error "plz check kubectl in PATH "
else
    node=$(kubectl get nodes | grep -vc "control")
    if [[ $node -eq 0 ]]; then
        error "plz check config and context of cluster"
    elif [[ $node -le 2 ]] && [[ $node -gt 0 ]]; then
        SINGLE_NODE="true"
        highlight "singlenode mode deploy"
    else
        # shellcheck disable=SC2034
        SINGLE_NODE="false"
        highlight "multinode mode deploy"
    fi
fi

# check function

check_op() {
    local OP_TYPE="$1"
    local PROJECT="$2"
    if [[ -n ${OP_TYPE} ]] && [[ -n ${PROJECT} ]]; then
        type "${OP_TYPE}_${PROJECT}" &>/dev/null || error "${OP_TYPE} [$PROJECT] NOT SUPPORT"
    else
        return 0
    fi
}

check_yum() {
    if ! command -v "$1" >/dev/null 2>&1; then
        sudo yum install "$1" -y -q || error "yum install $1 failed"
        highlight "$1 installed"
    fi
}

check_base_file() {
    check_yum jq
    check_yum uuid

    highlight "generate blueking app secret"
    "${bkScriptsPath}"/generate_app_secret.sh "${bkValuesPath}"/app_secret.yaml || error " generate app_secret failed\n check ${bkScriptsPath}/generate_app_secret.sh and ${bkValuesPath}/app_secret.yaml"
    if [[ $(yq e '.appSecret' "${bkValuesPath}"/app_secret.yaml | wc -l) -lt 16 ]]; then
        error "generate app_secret failed. plz check ${bkValuesPath}/app_secret.yaml"
    fi

    highlight "generate blueking apigateway rsa keypair"
    "${bkScriptsPath}"/generate_rsa_keypair.sh "${bkValuesPath}"/bkapigateway_builtin_keypair.yaml

    highlight "generate paas3 cluster role"
    "${bkScriptsPath}"/create_k8s_cluster_admin_for_paas3.sh
}

# tools

_kubectl_cmd() {
    # namspace
    if ! kubectl get ns "$NAMESPACE" 2>/dev/null; then
        echo "$NAMESPACE doesn't exist, auto creating......"
        kubectl create ns "$NAMESPACE" || error "无法创建 $NAMESPACE namespace，请检查kubeconfig权限"
    fi
    # image
    local image="${REGISTRY}/library/busybox:1.34.0"
    # limit
    local container_cpu="100m"
    local container_memory="256Mi"
    # pod name
    local pod
    pod="nsenter-$(env LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 6)"
    # version
    local m
    m=$(kubectl version --client -o yaml | awk -F'[ :"]+' '$2 == "minor" {print $3+0}')
    local generator=""
    if [ "$m" -lt 18 ]; then
        generator="--generator=run-pod/v1"
    fi
    # cmd
    local cmd='[ "nsenter", "--target", "1", "--mount", "--uts", "--ipc", "--net", "--pid", "--"'
    if [ $# -gt 0 ]; then
        while [ $# -gt 0 ]; do
            cmd="$cmd, \"$(
                echo "$1" |
                    awk '{gsub(/["\\]/,"\\\\&");gsub(/\x1b/,"\\u001b");printf "%s",last;last=$0"\\n"} END{print $0}'
            )\""
            shift
        done
        cmd="$cmd ]"
    else
        cmd="$cmd, \"bash\", \"-l\" ]"
    fi
    local overrides
    overrides="$(
        cat <<EOT
{
  "spec": {
    "hostPID": true,
    "hostNetwork": true,
    "containers": [
      {
        "securityContext": {
          "privileged": true
        },
        "image": "$image",
        "name": "nsenter",
        "stdin": true,
        "stdinOnce": true,
        "tty": true,
        "command": $cmd,
        "resources": {
          "limits": {
            "cpu": "${container_cpu}",
            "memory": "${container_memory}"
          },
          "requests": {
            "cpu": "${container_cpu}",
            "memory": "${container_memory}"
          }
        }
      }
    ]
  }
}
EOT
    )"
    kubectl run -n "$NAMESPACE" --image "$image" --restart=Never --rm -i --overrides="$overrides" "$pod" $generator
}

_paas() {
    deployPaaS="deploy/bkpaas3-apiserver-worker"
    paas_exec_cmd=${paas_exec_cmd:-"kubectl exec -n $NAMESPACE -i ${deployPaaS}"}
    case $1 in
    file_cp)
        shift
        # ../saas 1 layer
        tar cf - "$1" | ${paas_exec_cmd} -- tar xf - --strip-components=1
        ;;
    file_rm)
        shift
        ${paas_exec_cmd} -- rm "$1"
        ;;
    import_pre_created_instance)
        if ${paas_exec_cmd} -- python manage.py "$1" --service "default:redis" -f "$2"; then
            return 0
        else
            return 1
        fi
        ;;
    smart_tool)
        if ${paas_exec_cmd} -- python manage.py "$1" -f "$2" >"${bkSaaSPath}/$2-upload" 2>&1; then
            return 0
        else
            return 1
        fi
        ;;
    import_configvars)
        if ${paas_exec_cmd} -- python manage.py "$1" --app-code "$2" --module "$3" -f "$4"; then
            return 0
        fi
        ;;
    deploy_bkapp)
        SaaSEnv=${SaaSEnv:-"prod"}
        if ${paas_exec_cmd} -- python manage.py "$1" --app-code "$2" --module "$3" --env ${SaaSEnv} --revision "$4" >"${bkSaaSPath}/$2-${SaaSEnv}.$3"; then
            return 0
        fi
        ;;
    *)
        usage_and_exit 1
        ;;
    esac
}

# config_func
## to do 将逻辑改为用yq增量添加
_config_custom() {
    # get log_path
    local log_path=${DOCKER_ROOT_DIR:-""}
    local timeout=10
    highlight "create pod to get path of Docker Root Dir"
    while [[ -z $log_path ]]; do
        [[ $timeout -gt 0 ]] || error " fail to get Docker Root Dir \n ssh to cluster node and use command:\n \t DOCKER_ROOT_DIR=\$(ssh node_ip 'docker info | awk -F ": " '/Docker Root Dir/{print \$2}'')\n cover the DOCKER_ROOT_DIR befor re-execute this bash \n \t export DOCKER_ROOT_DIR=\$DOCKER_ROOT_DIR"
        log_path=$(_kubectl_cmd docker info | awk -F ": " '/Docker Root Dir/{dir=$2;gsub(/\r/,"",dir);printf "%s",dir}')
        sleep 4 && ((timeout--))
    done
    highlight "Docker Root Dir is $log_path"
    cat <<EOF | tee "${bkValuesPath}"/custom.yaml
imageRegistry: ${REGISTRY}
domain:
  bkDomain: $BK_DOMAIN
  bkMainSiteDomain: $BK_DOMAIN
$(
        [[ -z $log_path ]] && exit
        cat <<EEOF
apps:
  bkappFilebeat.containersLogPath: $log_path/containers
$(
            [[ ${SINGLE_NODE} == "false" ]] && exit
            cat <<EOFFF
  ingressNginx:
    hostNetwork: false
EOFFF
        )
EEOF
    )
EOF
}

_config_helm_repo() {
    if helm repo list 2>/dev/null | grep -q blueking; then
        echo "remove old helm repo: blueking"
        helm repo remove blueking
    fi
    helm repo add blueking "${REPOSITORY}"
    helm repo list
    helm repo update
}

_config_coredns() {
    if [[ -z $BK_DOMAIN ]]; then
        error "empty domain, plz check custom.yaml"
    fi
    # 更新coredns
    local IP1
    IP1=$(kubectl get svc -A -l app.kubernetes.io/instance=ingress-nginx -o jsonpath='{.items[0].spec.clusterIP}')
    "${bkScriptsPath}"/control_coredns.sh update "$IP1" bkrepo."$BK_DOMAIN" docker."$BK_DOMAIN" "$BK_DOMAIN" bkapi."$BK_DOMAIN" bkpaas."$BK_DOMAIN" bkiam-api."$BK_DOMAIN" bkiam."$BK_DOMAIN" apps."$BK_DOMAIN" bcs."$BK_DOMAIN" >/dev/null 2>&1
}

_config_bkrepo_res() {
    # 更新bkrepo的资源
    local imageURL repoUser repoPass
    repoUser=$(kubectl get secret -n "$NAMESPACE" bkpaas3-apiserver-bkrepo-envs -o go-template='{{.data.ADMIN_BKREPO_USERNAME | base64decode}}')
    repoPass=$(kubectl get secret -n "$NAMESPACE" bkpaas3-apiserver-bkrepo-envs -o go-template='{{.data.ADMIN_BKREPO_PASSWORD | base64decode}}')
    highlight "更新bkrepo的资源"
    imageURL=$(helm status -n "$NAMESPACE" bk-paas | awk -F '=' '/image/{url=$2;gsub(/ \\|"/,"",url);printf "%s",url}')
    kubectl run --rm \
        --env="BKREPO_USERNAME=$repoUser" \
        --env="BKREPO_PASSWORD=$repoPass" \
        --env="BKREPO_ENDPOINT=http://bkrepo.$BK_DOMAIN" \
        --env="BKREPO_PROJECT=bkpaas" \
        --image="${imageURL}" \
        -i bkpaas3-upload-runtime --command -- /bin/bash runtimes-download.sh \
        -n "$NAMESPACE" && highlight "upload_bkrepo_runtime"
}

_config_redis_res() {
    mkdir -p "${bkSaaSPath}"
    local step="${bkSaaSPath}"/saas_install_step
    if ! [[ -f "${bkSaaSPath}"/redis_custom.yaml ]]; then
        highlight "generate redis config yaml"
        local redis_secret
        redis_secret=$(kubectl get secret -n "$NAMESPACE" bk-redis -o jsonpath="{.data.redis-password}" | base64 --decode)
        local count=10
        while [[ ${count} -gt 0 ]]; do
            cat <<EOF | tee -a "${bkSaaSPath}"/redis_custom.yaml
plan: "0shared"
config: |
  {
    "recyclable": true
  }
credentials: |
  {
    "host": "bk-redis-master.${NAMESPACE}.svc.cluster.local",
    "port": 6379,
    "password": "${redis_secret}"
  }
---
EOF
            ((count--))
        done
        sed -i '$d' "${bkSaaSPath}"/redis_custom.yaml
    else
        echo "${bkSaaSPath}/redis_custom.yaml exist, skip generate"
    fi
    highlight "add PaaS redis resouce"
    _paas file_cp "${bkSaaSPath}"/redis_custom.yaml
    _paas import_pre_created_instance redis_custom.yaml
    _paas file_rm redis_custom.yaml
    highlight "config_redis_resource" >>"$step"
}

# upload_func
upload_runtime() {
    _config_bkrepo_res
}

upload_redis() {
    _config_redis_res
}

upload_agent() {
    local bucket repoUser repoPass
    bucket=$(kubectl get cm -n "$NAMESPACE" bk-nodeman-env-configmap -o go-template='{{.data.BKREPO_PUBLIC_BUCKET}}')
    repoUser=$(kubectl get cm -n "$NAMESPACE" bk-nodeman-env-configmap -o go-template='{{.data.BKREPO_USERNAME}}')
    repoPass=$(kubectl get cm -n "$NAMESPACE" bk-nodeman-env-configmap -o go-template='{{.data.BKREPO_PASSWORD}}')
    highlight "uploading agent package"
    # shellcheck disable=2015
    find "${bkAgentsPath}"/*.tgz -maxdepth 1 -print0 | xargs -0 -n 1 -I {} bash "${bkScriptsPath}"/bkrepo_tool.sh -u "$repoUser" -p "$repoPass" -i http://bkrepo."${BK_DOMAIN}"/generic -P "blueking" -n "${bucket}" -X PUT -R ./data/bkee/public/bknodeman/download -O -T {} && highlight "upload agent package success" || highlight "fail to upload agent package"
    highlight "uploading open tools"
    # shellcheck disable=2015
    find "${bkGsePath}"/*.tgz -maxdepth 1 -print0 | xargs -0 -n 1 -I {} bash "${bkScriptsPath}"/bkrepo_tool.sh -u "$repoUser" -p "$repoPass" -i http://bkrepo."${BK_DOMAIN}"/generic -P "blueking" -n "${bucket}" -X PUT -R ./data/bkee/public/bknodeman/download -O -T {} && highlight "upload open tools success" || highlight "fail to upload open tools."
}

upload_plugin() {
    nodemanPod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=bk-nodeman-backend-api | awk '/bk-nodeman-backend-api/{print $1}')
    if [[ -n ${nodemanPod} ]]; then
        highlight "uploading gse_plugin"
        kubectl exec -n "$NAMESPACE" "${nodemanPod}" -c bk-nodeman-backend-api -- mkdir -p official_plugin
        find "${bkPluginsPath}"/*.tgz -maxdepth 1 -print0 | xargs -0 -I {} kubectl -n "$NAMESPACE" cp {} "${nodemanPod}":./official_plugin/ -c bk-nodeman-backend-api
        kubectl exec -n "$NAMESPACE" "${nodemanPod}" -c bk-nodeman-backend-api -- python manage.py init_official_plugins
        kubectl exec -n "$NAMESPACE" "${nodemanPod}" -c bk-nodeman-backend-api -- rm -rf ./official_plugin/
    else
        echo "nodeman backend pod doesn't exist, \` kubectl get pods -n $NAMESPACE | grep nodeman \` for more detail"
    fi
}

# install_func

install_base() {
    if ! [[ -f ${bkValuesPath}/custom.yaml ]]; then
        highlight "generate custom.yaml"
        _config_custom
    else
        highlight "custom exist"
        cat "${bkValuesPath}"/custom.yaml
    fi
    _config_helm_repo

    if [[ $(kubectl get sc 2>/dev/null | wc -l) -eq 0 ]]; then
        highlight "installing localpv"
        helmfile -f "${bkBluekingPath}"/00-localpv.yaml.gotmpl apply >/dev/null || error "fail to install local-pv"
    else
        echo "storage controll exist, skip install local-pv-sc"
    fi
    if ! kubectl get svc -A | grep "ingress-nginx-controller"; then
        highlight "installing ingress"
        helmfile -f "${bkBluekingPath}"/00-ingress-nginx.yaml.gotmpl apply >/dev/null || error "fail to install ingress-nginx,\` kubectl get pods -A | grep ingress \` for more details"
    else
        echo "ingress-nginx-controller service exist, skip install ingress-nginx-controller"
    fi
    check_base_file

    highlight "update coredns ${BK_DOMAIN}"
    _config_coredns
    highlight "update coredns ${BK_DOMAIN} success, use \` ${bkScriptsPath}/control_coredns.sh list \`"

    highlight "installing blueking 7.0 base-backend"
    highlight "open a new terminal, use \` kubectl get pods -n $NAMESPACE -w\` to observe install process"
    helmfile -f "${bkBluekingPath}"/base.yaml.gotmpl apply >/dev/null || error "failed to install blueking base-backend, \` kubectl get pods -n $NAMESPACE \` for more details"

    kubectl delete pod --field-selector=status.phase==Succeeded -A >/dev/null
    "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "bk_cmdb,bk_job,bk_usermgr"
    "${bkScriptsPath}"/set_desktop_default_app.sh -a "bk_usermgr"

    highlight "请参考官方文档配置DNS"
    highlight "finish install blueking base-backend"
    highlight "SHOW BKPANEL & BKREPO INITIAL PASSWORD\n helm status -n $NAMESPACE bk-user \n helm status -n $NAMESPACE bk-repo"
}

install_nodeman() {
    highlight "install nodeman chart"
    helmfile -f "${bkBluekingPath}"/base-blueking.yaml.gotmpl -l name=bk-nodeman apply >/dev/null || error "failed to install nodeman, \` kubectl get pods -n $NAMESPACE | grep bk-nodeman \` for more details"
    "${bkScriptsPath}"/set_desktop_default_app.sh -a "bk_nodeman"
    "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "bk_nodeman"
    upload_agent
    upload_plugin
    kubectl delete pod --field-selector=status.phase==Succeeded -A >/dev/null
    highlight "finish"
}

_install_res() {
    local step="${bkSaaSPath}"/saas_install_step
    if ! [[ -f $step ]]; then
        touch "$step"
    fi
    if ! grep -q "config_redis_resource" "$step"; then
        _config_redis_res
        highlight "config_redis_resource" >>"$step"
    else
        highlight "skip config redis resource, because $step record it. \n if you want to create more shared redis resource, use ${PROGRAM} --upload redis"
    fi
}

_install_saas_mod() {
    # app_code：saas 应用名，格式为bk_xxxx;
    # env：saas模块，如defualt;
    # mod：saas包类型，image or package;
    # SaasEnv: saas安装环境，prod or stag;
    local app_code=$1 env=$2 saas_ns='' ns_name
    saas_name="${app_code}-${env}-${mod}-${version}"
    saas_log_file="${bkSaaSPath}/$app_code-${SaaSEnv}.${env}"
    saas_upload_log="${bkSaaSPath}/${file##*saas/}-upload"

    # saas_flag: 获取saas_ns是否存在，如果存在，且有pod，则不安装
    if [[ ${env} == "default" ]]; then
        ns_name="bkapp-${app_code//_/0us0}-${SaaSEnv}"
    else
        ns_name="bkapp-${app_code//_/0us0}-m-${env}-${SaaSEnv}"
    fi
    if kubectl get ns "$ns_name" >/dev/null 2>&1; then
        saas_ns=$(kubectl get ns "${ns_name}" -o jsonpath='{.metadata.name}')
    fi
    [[ -z ${saas_ns} ]] && local saas_flag=0
    local saas_flag=${saas_flag:-$(kubectl get pods -n "${saas_ns}" | wc -l)}

    if [[ ${saas_flag} -eq 0 ]]; then
        if [[ ${env} == "default" ]]; then
            # 只有defualt才需要，上传saas包，上传失败则跳过安装
            _paas file_cp "${file}"
            highlight "uploading ${file}"
            if ! _paas smart_tool "${file##*saas/}"; then
                _paas file_rm "${file##*saas/}"
                highlight "upload ${file} failed, see ${saas_upload_log} for more details"
                return 1
            fi
            _paas file_rm "${file##*saas/}"
        fi

        # 部署saas
        highlight "installing ${saas_name}"

        # 判定是否安装成功，如果不成功则清除saas_ns
        if _paas deploy_bkapp "$app_code" "${env}" "${mod}:${version}"; then
            highlight "${saas_name} installed"
            return 0
        else
            saas_ns=$(kubectl get ns "${ns_name}" -o jsonpath='{.metadata.name}')
            highlight "failed to install ${ns_name}, see ${saas_log_file} or for more details"
            highlight "clean ${saas_ns}"
            [[ -n ${saas_ns} ]] && kubectl delete ns "${saas_ns}"
            return 1
        fi
    else
        highlight "$saas_name has installed, use command below for more details \n kubectl get all -n ${saas_ns}"
        return 0
    fi
}

_install_saas() {
    mkdir -p "${bkSaaSPath}"
    # 检测文件
    local file
    file=$(find "${bkSaaSPath}"/"$1".tgz)
    [[ -n $file ]] || error "$1 doesn't exist in $bkSaaSPath"
    _install_res
    SaaSEnv=${SaaSEnv:-"prod"}

    # 检测saas-smart包的类型
    local mod
    if tar tf "$file" "$1/pkgs" &>/dev/null; then
        mod="package"
    else
        mod="image"
    fi

    local version
    version="$(tar xOf "$file" "$1"/app_desc.yaml | yq e '.app_version' -)"
    [[ -n $version ]] || error "$1 version is null, plz check md5sum $file"

    highlight "start install $1-${SaaSEnv}-${version}"
    case "$1" in
    "bk_itsm")
        _install_saas_mod "$1" default
        "${bkScriptsPath}"/set_desktop_default_app.sh -a "$1"
        "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "$1"
        ;;
    "bk_gsekit")
        _install_saas_mod "$1" default
        "${bkScriptsPath}"/set_desktop_default_app.sh -a "$1"
        "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "$1"
        ;;
    "bk_sops")
        if _install_saas_mod "$1" default; then
            "${bkScriptsPath}"/set_desktop_default_app.sh -a "$1"
            "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "$1"
            _install_saas_mod "$1" api
            _install_saas_mod "$1" callback
            _install_saas_mod "$1" pipeline
        else
            highlight "$1 default module install failed ,skip other module of $1 install"
        fi
        ;;
    "bk_lesscode")
        highlight "config bk_lesscode env"
        cat <<EOF | tee "${bkSaaSPath}/bk_lesscode_value.yaml" >/dev/null
env_variables:
- key: PRIVATE_NPM_REGISTRY
  value: http://bkrepo.${BK_DOMAIN}/npm/bkpaas/npm
  environment_name: _global_
  description: npm镜像源地址
- key: PRIVATE_NPM_USERNAME
  value: bklesscode
  environment_name: _global_
  description: npm账号用户名
- key: PRIVATE_NPM_PASSWORD
  value: blueking
  environment_name: _global_
  description: npm账号密码
- key: BKAPIGW_DOC_URL
  value: http://apigw.${BK_DOMAIN}/docs
  environment_name: _global_
  description: 云api文档地址
EOF
        _install_saas_mod "$1" default
        "${bkScriptsPath}"/set_desktop_default_app.sh -a "$1"
        "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "$1"
        ;;
    *)
        usage_and_exit 1
        ;;
    esac
}

install_itsm() {
    _install_saas bk_itsm
}
install_gsekit() {
    _install_saas bk_gsekit
}
install_sops() {
    _install_saas bk_sops
}
install_lesscode() {
    _install_saas bk_lesscode
}

install_saas() {
    highlight "to see the SaaS pod, open new terminal, \` kubectl get pods -Aw \`"
    _install_res

    # parallel install
    declare -A procArr
    install_itsm &
    procArr["bk_itsm"]="$!"
    highlight "installing itsm, pid is $!"
    install_gsekit &
    procArr["bk_gsekit"]="$!"
    highlight "installing gsekit, pid is $!"
    install_sops &
    procArr["bk_sops"]="$!"
    highlight "installing sops, pid is $!"
    install_lesscode &
    procArr["bk_lesscode"]="$!"
    highlight "installing lesscode, pid is $!"
    local timeout=10
    while ((${#procArr[@]})); do
        if [[ $timeout -gt 0 ]]; then
            sleep 90 && ((timeout--))
            for index in "${!procArr[@]}"; do
                if ! test -d /proc/"${procArr["$index"]}"/; then
                    echo "$index: pid ${procArr["$index"]} finished"
                    unset procArr["$index"]
                else
                    highlight "$index: pid ${procArr["$index"]} is running"
                fi
            done
        else
            echo "${!procArr[*]} timeout!!! kill pid ${procArr[*]}, "
            kill -9 ${procArr[*]}
            error "install saas timeout"
        fi
    done
}

install_bcs() {
    highlight "installing bcs"
    highlight "to see the bcs pod, open new terminal, \` kubectl get pods -n bcs-system -w \`"
    "${bkScriptsPath}"/set_desktop_default_app.sh -a "bk_bcs"
    "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "bk_bcs"
    helmfile -f "${bkBluekingPath}"/03-bcs.yaml.gotmpl sync >/dev/null || error "failed to install blueking bcs, \` kubectl get pods -n bcs-system\` for more details"
    kubectl delete pod --field-selector=status.phase==Succeeded -A >/dev/null
}

install_monitor() {
    highlight "to see the monitor pod, open new terminal, \` kubectl get pods -n $NAMESPACE -w | grep bk-monitor\`"
    highlight "installing bkmonitor"
    "${bkScriptsPath}"/set_desktop_default_app.sh -a "bk_monitorv3"
    "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "bk_monitorv3"
    helmfile -f "${bkBluekingPath}"/monitor-storage.yaml.gotmpl apply
    helmfile -f "${bkBluekingPath}"/04-bkmonitor.yaml.gotmpl sync >/dev/null || error "fail to install bkmonitor, \` kubectl get pods -n $NAMESPACE | grep bk-monitor \` for more details"
    kubectl delete pod --field-selector=status.phase==Succeeded -A >/dev/null
    highlight "finish\n 请安装agent后再手动部署bkmonitor-operator"
}

install_log() {
    highlight "to see the monitor pod, open new terminal, \` kubectl get pods -n $NAMESPACE -w | grep bk-log-search\`"
    highlight "installing bklog-search"
    "${bkScriptsPath}"/set_desktop_default_app.sh -a "bk_log_search"
    "${bkScriptsPath}"/add_user_desktop_app.sh -u "admin" -a "bk_log_search"
    helmfile -f "${bkBluekingPath}"/04-bklog-search.yaml.gotmpl sync || error "fail to install bklog-search, \` kubectl get pods -n $NAMESPACE | grep bk-log-search \` for more details"
    kubectl delete pod --field-selector=status.phase==Succeeded -A >/dev/null
    highlight "finish\n 请安装agent后再手动部署bklog-collector"
}

# host_func
host_blueking() {
    highlight "config DNS"
    cat <<EOFF
# 获取内网ip
IP1=\$(kubectl get pods -A -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].status.hostIP}')
IP2=\$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=bk-ingress-nginx -o jsonpath='{.items[0].status.hostIP}')
# 需要通过外网访问，获取外网IP
IP1=\$(ssh \$IP1 'curl -s ip.sb') 
IP2=\$(ssh \$IP2 'curl -s ip.sb')
# 配置本地host
cat <<EOF
\$IP1 $BK_DOMAIN
\$IP1 bkrepo.$BK_DOMAIN
\$IP1 docker.$BK_DOMAIN
\$IP1 bkpaas.$BK_DOMAIN
\$IP1 bkuser.$BK_DOMAIN
\$IP1 bkuser-api.$BK_DOMAIN
\$IP1 bkapi.$BK_DOMAIN
\$IP1 apigw.$BK_DOMAIN
\$IP1 bkiam.$BK_DOMAIN
\$IP1 bkiam-api.$BK_DOMAIN
\$IP1 cmdb.$BK_DOMAIN
\$IP1 job.$BK_DOMAIN
\$IP1 jobapi.$BK_DOMAIN
\$IP1 bknodeman.$BK_DOMAIN
\$IP1 bcs.$BK_DOMAIN
\$IP1 bkmonitor.$BK_DOMAIN
\$IP1 bklog.$BK_DOMAIN
\$IP1 apps.$BK_DOMAIN
\$IP1 lesscode.$BK_DOMAIN
EOF
EOFF
}

# exec_project
check_op "${OP_TYPE}" "${PROJECT}"
case "${OP_TYPE}" in
install)
    highlight "INSTALL:${PROJECT}"
    "install_${PROJECT}"
    ;;
host)
    highlight "host: ${PROJECT}"
    "host_${PROJECT}"
    ;;
upload)
    highlight "upload: ${PROJECT}"
    "upload_${PROJECT}"
    ;;
-*)
    error "unrecognized params: $1"
    ;;
*)
    usage_and_exit 0
    ;;
esac
