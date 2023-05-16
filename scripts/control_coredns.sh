#!/bin/bash
#
# add/update/delete coredns hosts config

NAMESPACE=kube-system
CONFIGMAP=coredns

usage() {
  cat << EOF
用法:
   $0 <control> <ip> <hosts1> <host2> <host3> <...>
    control        [ add      增加host解析规则                              ] 
                   [ del      删除host解析规则                              ]
                   [ update   更新解析规则                                  ]
                   [ list     显示hosts配置                                 ]
                   [ rollback 回滚corefile配置，备份文件/tmp/corefile目录中 ]
    eg: ./$0 add 1.1.1.1 test-paas.bktencent.com
        ./$0 del test-paas.bktencent.com
        ./$0 rollback /tmp/corefile/corefile.xxx
EOF
}
error() {
  echo -e "[ERROR]$(date '+%Y-%m-%d %H:%M:%S'): $*" 1>&2
  exit 1
}

info() {
  echo -e "[INFO]$(date '+%Y-%m-%d %H:%M:%S'): $*" 
}

#获取coredns configmap 配置文件
get_coredns_corefile() { 
  kubectl get cm "${CONFIGMAP}" -o json -n "${NAMESPACE}" | jq -r .data.Corefile 
  if [ $? -ne 0 ]; then
     error "获取coredns configmap 配置文件失败, 命令: \n\
       kubectl get cm "${CONFIGMAP}" -o json -n "${NAMESPACE}" | jq -r .data.Corefile"
  fi
}

multiline_to_single() {
  awk '{printf "%s\\n",$0}'
}

multiline_to_single_with_quote() {
  awk -v dq='"' 'BEGIN{printf "%s", dq}{printf "%s\\n",$0}END{printf "%s", dq}'
}

check_env() {
  if ! which kubectl  >/dev/null 2>&1; then
      error "未安装kubectl命令"
  fi
  
  if ! which jq >/dev/null 2>&1; then
     error "未安装jq命令"
  fi
}

check_ip() {
  if ! [[ $1 =~ ^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$ ]]; then
    usage
    error "IP 地址格式不对"
    exit 1
  fi
}

backup_corefile() {
  local backfile="corefile.$(date '+%Y%m%d%H%M%S')"
  mkdir -p /tmp/corefile/
  kubectl get cm "${CONFIGMAP}" -o json -n "${NAMESPACE}" | jq .data.Corefile > /tmp/corefile/${backfile}
}

rollback_corefile() {
  local config=/data/Corefile
  if [ ! -f "$1" ]; then
      error "$1 文件不存在，$(usage)"
  fi
  kubectl patch cm $CONFIGMAP -n $NAMESPACE --type='json' -p '[{"op":"replace","path":"'"${config}"'","value": '"$(cat $1)"'}]'
}

prepare_hosts_str() {
  local space=" " host
  for host in "$@"; do
    printf "%8s%s %s\n" "$space" "$IP" "$host"
  done
}


check_domain_in_host() {
  local coredns_str=$(get_coredns_corefile)
  local ret=1

  for domain in "$@"; do
    if echo "${coredns_str}" | grep -q " ${domain}$";then
       ret=0
    fi
  done 
  return ${ret}
}

add_coredns_hosts() {
  local config=/data/Corefile
  local coredns_str=$(get_coredns_corefile)
  local has_hosts=$(echo "${coredns_str}" | grep " *hosts *{")
  local new_str=""

   
  if [[ -n "${has_hosts}" ]]; then
    local line=${1%??}
    new_str=$(echo "${coredns_str}" | sed -e '/hosts *{/a\'"$line"'' | multiline_to_single_with_quote)
  else
    new_str=$(echo "${coredns_str}" | sed -e '/prometheus/a\    hosts {\n'"$1"'        fallthrough\n    }\n' | multiline_to_single_with_quote)
  fi
  kubectl patch cm $CONFIGMAP -n $NAMESPACE --type='json' -p '[{"op":"replace","path":"'"${config}"'","value": '"${new_str}"'}]'
}

del_coredns_host() {
  local coredns_str=$(get_coredns_corefile)
  local new_str=${coredns_str}
  local config=/data/Corefile

  for domain in "$@"; do
    if echo "${coredns_str}" | grep -q " ${domain}$";then
       new_str=$(echo "${new_str}" | sed -e "/ ${domain}$/d")
    fi
  done
  new_str=$(echo "${new_str}" | multiline_to_single_with_quote)
  #echo "$new_str"
  kubectl patch cm $CONFIGMAP -n $NAMESPACE --type='json' -p '[{"op":"replace","path":"'"${config}"'","value": '"${new_str}"'}]'
}

list_corefile_hosts () {
    local hosts=$(kubectl get cm "${CONFIGMAP}" -o json -n "${NAMESPACE}" | jq -r .data.Corefile \
                  | awk '/hosts *{/,/fallthrough/ { if(/[0-9]/) print }')
    if [[ -n "$hosts" ]]; then
       printf "$hosts"
       echo 
    else
       return 1
    fi
}

#script start 
check_env 
CONTROL=$1
shift

case ${CONTROL} in
  "add" )
    IP=$1
    check_ip ${IP}
    shift
    backup_corefile
    check_domain_in_host $@ && error "host 已经在配置中存在，如果需要更新请使用update, \n" 
    add_coredns_hosts "$(prepare_hosts_str "$@" | multiline_to_single)"
    check_domain_in_host $@ && ( info "host $@ 添加成功" && list_corefile_hosts ) || error "host $@ 添加失败"
    ;;
  "update" )
    IP=$1
    check_ip ${IP}
    shift
    backup_corefile
    del_coredns_host $@
    add_coredns_hosts "$(prepare_hosts_str "$@" | multiline_to_single)"
    check_domain_in_host $@ && ( info "host $@ 更新成功" && list_corefile_hosts ) || error "host $@ 更新失败"
    ;;
  "del" )
     backup_corefile
     del_coredns_host $@ && ( info "host $@ 删除成功" && list_corefile_hosts ) || error "host $@ 删除失败"
    ;;
  "list" )
     list_corefile_hosts
    ;;
  "rollback" )
     rollback_corefile $1 && ( info "回滚成功" && list_corefile_hosts ) || error "回滚失败"
     ;;
  * )
    usage
    exit 1
    ;;
esac


