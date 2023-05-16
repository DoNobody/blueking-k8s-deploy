#!/bin/bash
#
#check kubernetes environment


#kubernetes 版本号 > v1.17
KUBERNETES_MINIMUM_VERSION=v1.17

#kubernetes 最小资源
KUBERNETES_ALLOC_CPU=20
KUBERNETES_ALLOC_MEM=40    #单位GB 
KUBERNETES_ALLOC_PODS=100

#debug模式
DEBUG=false
#DEBUG=true


error() {
  echo -e "[\033[31mERROR\033[0m]$(date '+%Y-%m-%d %H:%M:%S'): $*" 1>&2
  exit 1
}

info() {
  echo -e "[\033[32mINFO\033[0m]$(date '+%Y-%m-%d %H:%M:%S'): $*" 
}

debug() {
  if ${DEBUG}; then
    echo -e "[DEBUG]$(date '+%Y-%m-%d %H:%M:%S'): $*" 
  fi
}

#检查kubernetes的版本
check_kubernetes_version() {
 
  if ! which kubectl > /dev/null 2>&1; then
    error "没有发现kubectl 命令."
  fi

  version=$(kubectl version | awk -F, '/Server Version/ { print $3 }' | grep -o "v[0-9]\.[0-9]*")
  if [[  -z "${version}" ]]; then
     error "kubectl version 得到server 版本号为空."
  fi

  if [ x"$(echo "${version} ${KUBERNETES_MINIMUM_VERSION}" | tr " " "\n" | sort -rV | head -n 1)" = x"${KUBERNETES_MINIMUM_VERSION}" ]; then
     error "Kubernetes version 版本太低 < ${KUBERNETES_MINIMUM_VERSION}, 当前版本:${version}"
  fi
  info "kubernetes 版本检查正常."
}

#检查kubernetes的可分配cpu
check_kubernetes_cpu() {
  local use_cpu=0
  local total_cpu=0
  local per=0
  local sum_use_cpu=0
  local sum_total_cpu=0
  local sum_free_cpu=0

  debug "$(printf "%-30s%-16s%-16s%-16s\n" "NODE NAME" "TOTAL CPU" "USE CPU" "FREE CPU" )"
  for node in $(kubectl get nodes | grep -v master  | grep -w "Ready" | awk '{ print $1 }')
  do
    read use_cpu per <<<$(kubectl describe node ${node}  | grep -A 4 "Allocated resources"  | grep cpu | awk '{ print $2,$3 }')
    #取整
    use_cpu=$(echo "${use_cpu}" | tr -d 'm')
    per=$(echo "${per}" | grep -o "[0-9]*")
    total_cpu=$(echo "${use_cpu}/${per}*100" | bc)
    free_cpu=$(echo "${total_cpu}-${use_cpu}" | bc)
    sum_total_cpu=$(echo "${sum_total_cpu}+${total_cpu}" | bc)
    sum_use_cpu=$(echo "${sum_use_cpu}+${use_cpu}" | bc)
    sum_free_cpu=$(echo "${sum_free_cpu}+${free_cpu}" | bc)
    debug "$(printf "%-30s%-16s%-16s%-16s\n"  "${node}" "${total_cpu}" "${use_cpu}" "${free_cpu}")"
    if [ ${sum_free_cpu} -ge $(echo "${KUBERNETES_ALLOC_CPU}*1000" | bc) ]; then
      info "kubernetes 集群cpu资源检查正常."
      return 
    fi
  done
  error "kubernetes 集群cpu资源检查异常，可用cpu: ${sum_free_cpu}, 需要cpu: ${KUBERNETES_ALLOC_CPU}000"
  debug "$(printf "%s\n" "-------------------------------------------------------------------")"
  debug "$(printf "%-30s%-16s%-16s%-16s\n" "SUM" "${sum_total_cpu}" "${sum_use_cpu}" "${sum_free_cpu}")"
}

#检查kubernetes的可分配mem
check_kubernetes_mem() {
  local use_mem=0
  local total_mem=0
  local per=0
  local sum_use_mem=0
  local sum_total_mem=0
  local sum_free_mem=0

  debug "$(printf "%-30s%-16s%-16s%-16s\n" "NODE NAME" "TOTAL MEM" "USE MEM" "FREE MEM" )"
  for node in $(kubectl get nodes | grep -v master  | grep -w "Ready" | awk '{ print $1 }')
  do
    read use_mem per <<<$(kubectl describe node ${node}  | grep -A 5 "Allocated resources"  | grep mem | awk '{ print $2,$3 }')
    #取整
    use_mem=$(echo "${use_mem}" | grep -o "[0-9]*")
    per=$(echo "${per}" | grep -o "[0-9]*")
    total_mem=$(echo "${use_mem}/${per}*100" | bc)
    free_mem=$(echo "${total_mem}-${use_mem}" | bc)
    sum_total_mem=$(echo "${sum_total_mem}+${total_mem}" | bc)
    sum_use_mem=$(echo "${sum_use_mem}+${use_mem}" | bc)
    sum_free_mem=$(echo "${sum_free_mem}+${free_mem}" | bc)
    debug "$(printf "%-30s%-16s%-16s%-16s\n"  "${node}" "${total_mem}" "${use_mem}" "${free_mem}")"
    if [ ${sum_free_mem} -ge $(echo "${KUBERNETES_ALLOC_MEM}*1000" | bc) ]; then
      info "kubernetes 集群mem资源检查正常."
      return
    fi
  done
  debug "$(printf "%s\n" "-------------------------------------------------------------------")"
  debug "$(printf "%-30s%-16s%-16s%-16s\n" "SUM" "${sum_total_mem}" "${sum_use_mem}" "${sum_free_mem}")"
  error "kubernetes 集群mem资源检查异常，可用mem: ${sum_free_mem}, 需要mem: ${KUBERNETES_ALLOC_MEM}000"
}

#检查kubernetes的可分配pod数量
check_kubernetes_pods() {

  local total_pods=0
  local use_pods=0
  local free_pods=0
  local sum_total_pods=0
  local sum_use_pods=0
  local sum_free_pods=0
  
  debug "$(printf "%-30s%-16s%-16s%-16s\n" "NODE NAME" "TOTAL PODS" "USE PODS" "FREE PODS" )"
  for node in $(kubectl get nodes | grep -v master  | grep -w "Ready" | awk '{ print $1 }')
  do
    total_pods=$(kubectl describe node ${node}  | grep -A 8 "Allocatable"  | grep pods | awk '{ print $2 }')
    use_pods=$(kubectl describe node ${node}  | grep  "Non-terminated Pods"   | awk '{ print $3 }' | grep -o "[0-9]*")
    #取整
    free_pods=$(echo "${total_pods}-${use_pods}" | bc)
    sum_total_pods=$(echo "${sum_total_pods}+${total_pods}" | bc)
    sum_use_pods=$(echo "${sum_use_pods}+${use_pods}" | bc)
    sum_free_pods=$(echo "${sum_free_pods}+${free_pods}" | bc)
    debug "$(printf "%-30s%-16s%-16s%-16s\n"  "${node}" "${total_pods}" "${use_pods}" "${free_pods}")"
    if [ ${sum_free_pods} -ge $(echo "${KUBERNETES_ALLOC_PODS}" | bc) ]; then
      info "kubernetes 集群pods资源检查正常."
      return
    fi
  done
  debug "$(printf "%s\n" "-------------------------------------------------------------------")"
  debug "$(printf "%-30s%-16s%-16s%-16s\n" "SUM" "${sum_total_pods}" "${sum_use_pods}" "${sum_free_pods}")"
  error "kubernetes 集群pods资源检查异常，可用pods: ${sum_free_pods}, 需要pods: ${KUBERNETES_ALLOC_PODS}"
}




check_kubernetes_version
check_kubernetes_cpu
check_kubernetes_mem
check_kubernetes_pods
