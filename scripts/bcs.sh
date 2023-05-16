#!/usr/bin/env bash
# Usage: Install BCS

# bcs
BCS_DIR="$HOME/.bcs"
BK_HOME=${BK_HOME:-/data/bcs}
bcs_override=${bcs_override:-false}
bcs_sysctl=${bcs_sysctl:-1}
# yum 
MIRROR_IP=${MIRROR_IP:-null}
MIRROR_URL=${MIRROR_URL:-https://mirrors.tencent.com}
# helm  
BKREPO_URL=${BKREPO_URL:-null}
# docker  
DOCKER_LIB=${DOCKER_LIB:-${BK_HOME}/lib/docker}
DOCKER_VERSION=${DOCKER_VERSION:-19.03.9}
DOCKER_LIVE_RESTORE=${DOCKER_LIVE_RESTORE:-false}
REPO_MIRRORS=${REPO_MIRRORS:-[\"https://mirror.ccs.tencentyun.com\"]}
DOCKER_BRIDGE=${DOCKER_BRIDGE:-null}
BK_PUBLIC_REPO=${BK_PUBLIC_REPO:-hub.bktencent.com}
BK_RELEASE_REPO=${BK_RELEASE_REPO:-hub.bktencent.com/blueking}
# k8s 
KUBELET_LIB=${KUBELET_LIB:-${BK_HOME}/lib/kubelet}
BCS_K8S_CTRL_IP=${BCS_K8S_CTRL_IP:-$LAN_IP}
K8S_VER=${K8S_VER:-1.20.11}
K8S_SVC_CIDR=${K8S_SVC_CIDR:-10.96.0.0/12}
K8S_POD_CIDR=${K8S_POD_CIDR:-10.244.0.0/16}
K8S_EXTRA_ARGS=${K8S_EXTRA_ARGS:-allowed-unsafe-sysctls: 'net.ipv4.tcp_tw_reuse'}
ETCD_LIB=${ETCD_LIB:-${BK_HOME}/lib/etcd}
BCS_CP_WORKER=${BCS_CP_WORKER:-0}
K8S_CNI=${K8S_CNI:-flannel}
join_cmd_b64=${join_cmd_b64:-null}
cluster_env=${cluster_env:-null}
master_join_cmd_b64=${master_join_cmd_b64:-null}

# 安全模式
set -euo pipefail 

# 重置PATH
PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
#SELF_DIR=$(dirname "$(readlink -f "$0")")
#PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0
OP_TYPE=
LAN_IP=

# 全局默认变量
PROJECTS=( bcsenv op helm k8smaster k8snode )
PROJECT=
ON_CLOUD="bare-metal"

# error exit handler
err_trap_handler () {
    MYSELF="$0"
    LASTLINE="$1"
    LASTERR="$2"
    echo "${MYSELF}: line ${LASTLINE} with exit code ${LASTERR}" >&2
}
trap 'err_trap_handler ${LINENO} $?' ERR

usage () {
    cat <<EOF
用法: 
    bcs.sh  [ -h --help -?      查看帮助 ]
            [ -i, --install     支持安装模块(${PROJECTS[*]}) ]
            [ -c, --clean       清理安装模块(${PROJECTS[*]}) ]
            [ -r, --render      渲染模块配置(${PROJECTS[*]}) ]
            [ -v, --version     [可选] 查看脚本版本号 ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "[INFO]: $*"
}

warning () {
    echo "[WARN]: $*" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "bcs.sh version $VERSION"
}

highlight () {
    echo -e "\033[7m  $*  \033[0m"
}

error () {
    highlight "[ERROR]: $*" 1>&2
    usage_and_exit 1
}

ok_bcs () {
    cat <<EOF

$(
    log "LAN_IP: $LAN_IP"
    highlight "Welcome to BCS on $ON_CLOUD"
)
EOF
}

bye_bcs () {
    cat <<EOF

$(
    highlight "Finish"
)
EOF
}

_retry () {
    local n=1
    local max=2
    local delay=1
    while true; do
        if "$@"; then
            break
        elif (( n < max )); then
                ((n++))
                warning "Command failed. Attempt $n/$max:"
                sleep $delay;
        else
                error "The command $* has failed after $n attempts."
        fi
    done
}

### 运维相关配置

install_op () {
    _install_common
    op_kubeadm
    op_kubectl
    op_minikube
    op_helm
    op_bkrepo "${BKREPO_URL}"
    log "Complete"
}

_install_common () {
    if ! rpm -q bash-completion &>/dev/null; then 
        yum -y install bash-completion || error "Install bash-completion Failed"
    fi
}

op_kubeadm () {
    if command -v kubeadm &>/dev/null; then
    sed -ri '/bcs config begin for kubeadm/,/bcs config end for kubeadm/d' "$BCS_DIR/bcs.env"
    cat >> "$BCS_DIR/bcs.env" << 'EOF'
# bcs config begin for kubeadm
# kubeadm 命令补全
source <(kubeadm completion bash)
# bcs config end for kubeadm
EOF
    fi
}

op_kubectl () {
    if command -v kubectl &>/dev/null; then
    sed -ri '/bcs config begin for kubectl/,/bcs config end for kubectl/d' "$BCS_DIR/bcs.env"
    cat >> "$BCS_DIR/bcs.env" << 'EOF'
# bcs config begin for kubectl
# kubectl 命令补全
source <(kubectl completion bash)
# bcs config end for kubectl
EOF
    fi
}

op_minikube () {
    if command -v minikube &>/dev/null; then
    sed -ri '/bcs config begin for minikube/,/bcs config end for minikube/d' "$BCS_DIR/bcs.env"
    cat >> "$BCS_DIR/bcs.env" << 'EOF'
# bcs config begin for minikube
# minikube 命令补全
source <(minikube completion bash)
# bcs config end for minikube
EOF
    fi
}

op_helm () {
    if command -v helm &>/dev/null; then
    sed -ri '/bcs config begin for helm/,/bcs config end for helm/d' "$BCS_DIR/bcs.env"
    cat >> "$BCS_DIR/bcs.env" << 'EOF'
# bcs config begin for helm
# Helm 命令补全
source <(helm completion bash)
# Helm 激活对 OCI 的支持
export HELM_EXPERIMENTAL_OCI=1
# bcs config end for helm
EOF
    fi
}

op_bkrepo () {
    local BKREPO_URL="$1"
    if command -v helm &>/dev/null; then
        if [[ $BKREPO_URL == "null" ]]; then
            warning "BKREPO_URL is ${BKREPO_URL}, skipping"
            return 0
        fi
        highlight "Add bkrepo: ${BKREPO_URL}"
        helm repo add bk "${BKREPO_URL}"
        helm repo update
        log "bkrepo added"
    else
        warning "Add bkrepo: helm not found, skipping"
        return 0
    fi
}

clean_op () {
    helm repo remove bkrepo || warning "remove bkrepo failed"
    clean_bcsenv
}

### 环境/系统初始化

install_bcsenv () {
    local bcs_override=true
    _on_cloud
    _add_sysctl
    _add_hosts
    cat -n "$BCS_DIR/bcs.env"
    _init_kubeadmconfig
    log "Complete"
}

_init_kubeadmconfig () {
    local join_cmd
    local node_name
    local node_type
    # 参数检查
    [[ -n ${BCS_K8S_CTRL_IP} ]] || error "Kubernetes控制平面IP未指定"
    if [[ ${join_cmd_b64} != "null" ]]; then
        join_cmd="$(echo -n "${join_cmd_b64}" | base64 -d)"
        echo -n "${join_cmd}" | grep -q "kubeadm join" || error "添加节点命令参数异常"
        node_name="node-$(echo "$LAN_IP" | tr '.' '-')"
        node_type="JoinConfiguration"
    elif [[ ${master_join_cmd_b64} != "null" ]]; then
        join_cmd="$(echo -n "${master_join_cmd_b64}" | base64 -d)"
        echo -n "${join_cmd}" | grep -q "kubeadm join" || error "master扩容命令参数异常"
        node_name="master-$(echo "$LAN_IP" | tr '.' '-')"
        node_type="JoinConfiguration"
    else
        node_name="master-$(echo "$LAN_IP" | tr '.' '-')"
        node_type="InitConfiguration"
    fi
    
    cat > "$BCS_DIR/kubeadm-config" << EOF
apiVersion: kubeadm.k8s.io/$(
    [[ $K8S_VER =~ ^1.12 ]] && { echo "v1alpha3"; exit; }
    [[ $K8S_VER =~ ^1.1[3|4] ]] && { echo "v1beta1"; exit; }
    [[ $K8S_VER =~ ^1.(1[5-9]|2[0-2]) ]] && { echo "v1beta2"; exit; }
)
apiServer:
  extraArgs:
    authorization-mode: Node,RBAC
  timeoutForControlPlane: 4m0s
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controlPlaneEndpoint: k8s-api.bcs.local:6443
controllerManager: {}
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: ${ETCD_LIB}
imageRepository: ${BK_PUBLIC_REPO}/k8s.gcr.io
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VER}
networking:
  dnsDomain: cluster.local
  podSubnet: ${K8S_POD_CIDR}
  serviceSubnet: ${K8S_SVC_CIDR}
scheduler: {}
---
apiVersion: kubeadm.k8s.io/$(
    [[ $K8S_VER =~ ^1.12 ]] && { echo "v1alpha3"; exit; }
    [[ $K8S_VER =~ ^1.1[3|4] ]] && { echo "v1beta1"; exit; }
    [[ $K8S_VER =~ ^1.(1[5-9]|2[0-2]) ]] && { echo "v1beta2"; exit; }
)
kind: $node_type
nodeRegistration:
  name: $node_name
  kubeletExtraArgs:
    root-dir: ${KUBELET_LIB}
$(
    if [[ -n ${K8S_EXTRA_ARGS} ]]; then
        cat << EOFF
    ${K8S_EXTRA_ARGS}
EOFF
    fi
)
$(
    if [[ $K8S_VER =~ ^1.12 ]]; then
        cat << EOFF
    pod-infra-container-image: ${BK_PUBLIC_REPO}/k8s.gcr.io/pause:3.1
EOFF
    fi
    if [[ $K8S_VER =~ ^1.12 ]] && [[ $node_type == "JoinConfiguration" ]]; then
        cat << EOFF
#discoveryToken: $(echo ${join_cmd} | grep -Po '(?<=discovery-token-ca-cert-hash )sha256:[a-z0-9]{64}' )
discoveryTokenAPIServers:
- k8s-api.bcs.local:6443
discoveryTokenUnsafeSkipCAVerification: true
tlsBootstrapToken: $(echo ${join_cmd} | grep -Po '(?<=token )[a-z0-9.]{23}' )
token: $(echo ${join_cmd} | grep -Po '(?<=token )[a-z0-9.]{23}' )
EOFF
    elif [[ $node_type == "JoinConfiguration" ]]; then
        cat << EOFF
discovery:
  bootstrapToken:
    apiServerEndpoint: k8s-api.bcs.local:6443
    caCertHashes:
    - $(echo ${join_cmd} | grep -Po '(?<=discovery-token-ca-cert-hash )sha256:[a-z0-9]{64}' )
    token: $(echo ${join_cmd} | grep -Po '(?<=token )[a-z0-9.]{23}' )
EOFF
        if [[ $node_name =~ ^master ]]; then
            cat << EOFF
controlPlane:
  certificateKey: $(echo ${join_cmd} | grep -Po '(?<=certificate-key )[a-z0-9]{64}' )
EOFF
        fi
    fi
)
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
$(
    if ! [[ $BCS_K8S_CTRL_IP =~ $LAN_IP ]]; then
        cat << EOFF
ipvs:
  excludeCIDRs:
  - "$BCS_K8S_CTRL_IP/32"
EOFF
    fi
)
EOF
      highlight "$node_name: init bcsenv"
}

_on_baremetal () {
    log "NOT on cloud"
    [[ -n $LAN_IP ]] || LAN_IP=$(ip -4 -o route get 10/8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')
    _init_bcsenv
}

_on_cloud () {
    install -dv "${BCS_DIR}" || warning "create ${BCS_DIR} dir failed"
    touch "${BCS_DIR}/bcs.env"

    if [[ $bcs_override != "true" ]]; then
        #set -a
        # shellcheck disable=SC1091
        source "$BCS_DIR/bcs.env"
        #set +a
        [[ -z $LAN_IP ]] || return 0 
    fi

    QCLOUD_META_API="http://169.254.0.23/latest/meta-data"
    AWS_META_API="http://169.254.169.254/latest/meta-data"
    local META_API
    if curl -m 2 -qIfs "${QCLOUD_META_API}" >/dev/null; then
        ON_CLOUD="qcloud"
        META_API="${QCLOUD_META_API}"
    elif curl -m 2 -Ifs "${AWS_META_API}" >/dev/null; then
        ON_CLOUD="aws"
        META_API="${AWS_META_API}" 
    else
        _on_baremetal
        return 0
    fi

    LAN_IP="$( curl -sSf ${META_API}/local-ipv4 )"
    [[ -n $LAN_IP ]] || LAN_IP=$(ip -4 -o route get 10/8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')

    case "$ON_CLOUD" in
        qcloud)
            mirror_url="http://mirrors.tencentyun.com"
            ;;
        aws)
            mirror_url="https://mirrors.tencent.com"
            ;;
    esac

    _init_bcsenv
}

_init_bcsenv () {
    highlight "Add envfile"
    # shellcheck disable=SC1090
    [[ ${cluster_env} == "null" ]] || source <( echo "${cluster_env}" | base64 -d )
    [[ -n ${MIRROR_URL} ]] || MIRROR_URL=${mirror_url}
    # local LAN_IP="$1"
    # local MIRROR_URL="$2"
    cat > "$BCS_DIR/bcs.env" << EOF
# bcs config begin for $ON_CLOUD
ON_CLOUD="${ON_CLOUD}"
BCS_DIR="${BCS_DIR}"
BK_HOME="${BK_HOME}"
bcs_sysctl="${bcs_sysctl}"
MIRROR_IP="${MIRROR_IP}"
MIRROR_URL="${MIRROR_URL}"
BKREPO_URL="${BKREPO_URL}"
DOCKER_LIB="${DOCKER_LIB}"
DOCKER_VERSION="${DOCKER_VERSION}"
DOCKER_LIVE_RESTORE="${DOCKER_LIVE_RESTORE}"
REPO_MIRRORS='${REPO_MIRRORS}'
DOCKER_BRIDGE="${DOCKER_BRIDGE}"
BK_PUBLIC_REPO="${BK_PUBLIC_REPO}"
BK_RELEASE_REPO="${BK_RELEASE_REPO}"
KUBELET_LIB="${KUBELET_LIB}"
K8S_VER="${K8S_VER}"
K8S_SVC_CIDR="${K8S_SVC_CIDR}"
K8S_POD_CIDR="${K8S_POD_CIDR}"
K8S_EXTRA_ARGS="${K8S_EXTRA_ARGS}"
ETCD_LIB="${ETCD_LIB}"
LAN_IP="${LAN_IP}"
BCS_K8S_CTRL_IP="${BCS_K8S_CTRL_IP:-$LAN_IP}"
# bcs config end for $ON_CLOUD
EOF
    sed -ri "/bcs config begin for $ON_CLOUD/,/bcs config end for $ON_CLOUD/d" "$HOME/.bashrc"
    cat >> "$HOME/.bashrc" << EOF
# bcs config begin for $ON_CLOUD
source "${BCS_DIR}/bcs.env"
# bcs config end for $ON_CLOUD
EOF
# shellcheck disable=SC1091
source "${BCS_DIR}/bcs.env"
}

_add_sysctl () {
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ $VERSION_ID != "2.2" ]]; then
        echo br_netfilter ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh nf_conntrack | xargs -n1 modprobe
    fi
    if [[ -f /etc/tlinux-release ]] && [[ $K8S_CNI == "ws_flannel" ]]; then
        if lsmod | grep -q vlxan; then
            rmmod vxlan
        elif lsmod | grep -q vlxan; then
            error "vxlan模块卸载失败"
        fi
        modprobe vxlan udp_port=4789
        log "Winodws flannel VXLAN using $(cat /sys/module/vxlan/parameters/udp_port)"
    fi
    [[ ${bcs_sysctl} == "1" ]] || return 0
    highlight "Add sysctl"
    TOTAL_MEM=$(free -b | awk 'NR==2{print $2}')
    TOTAL_MEM=${TOTAL_MEM:-$(( 16 * 1024 * 1024 *1024 ))}
    PAGE_SIZE=$(getconf PAGE_SIZE)
    PAGE_SIZE=${PAGE_SIZE:-4096}
    THREAD_SIZE=$(( PAGE_SIZE << 2 ))
    sed -ri.bcs.bak '/bcs config begin/,/bcs config end/d' /etc/sysctl.conf
    cat >> "/etc/sysctl.conf" << EOF
# bcs config begin
# 系统中每一个端口最大的监听队列的长度,这是个全局的参数,默认值128太小，32768跟友商一致
net.core.somaxconn=32768
# 大量短连接时，开启TIME-WAIT端口复用
net.ipv4.tcp_tw_reuse=1
# TCP半连接队列长度。值太小的话容易造成高并发时客户端连接请求被拒绝
net.ipv4.tcp_max_syn_backlog=8096
# RPS是将内核网络rx方向报文处理的软中断分配到合适CPU核，以提升网络应用整体性能的技术。这个参数设置RPS flow table大小
fs.inotify.max_user_instances=8192
# inotify watch总数量限制。调大该参数避免"Too many open files"错误
fs.inotify.max_user_watches=524288
# 使用bpf需要开启
net.core.bpf_jit_enable=1
# 使用bpf需要开启
net.core.bpf_jit_harden=1
# 使用bpf需要开启
net.core.bpf_jit_kallsyms=1
# 用于调节rx软中断周期中内核可以从驱动队列获取的最大报文数，以每CPU为基础有效，计算公式(dev_weight * dev_weight_tx_bias)。主要用于调节网络栈和CPU在tx上的不对称
net.core.dev_weight_tx_bias=1
# socket receive buffer大小
net.core.rmem_max=16777216
# RPS是将内核网络rx方向报文处理的软中断分配到合适CPU核，以提升网络应用整体性能的技术。这个参数设置RPS flow table大小
net.core.rps_sock_flow_entries=8192
# socket send buffer大小
net.core.wmem_max=16777216
# 避免"neighbor table overflow"错误(发生过真实客户案例，触发场景为节点数量超过1024，并且某应用需要跟所有节点通信)
net.ipv4.neigh.default.gc_thresh1=2048
# 同上
net.ipv4.neigh.default.gc_thresh2=8192
# 同上
net.ipv4.neigh.default.gc_thresh3=16384
# orphan socket是应用以及close但TCP栈还没有释放的socket（不包含TIME_WAIT和CLOSE_WAIT）。 适当调大此参数避免负载高时报'Out of socket memory'错误。32768跟友商一致。
net.ipv4.tcp_max_orphans=32768
# 代理程序(如nginx)容易产生大量TIME_WAIT状态的socket。适当调大这个参数避免"TCP: time wait bucket table overflow"错误。
net.ipv4.tcp_max_tw_buckets=16384
# TCP socket receive buffer大小。 太小会造成TCP连接throughput降低
net.ipv4.tcp_rmem=4096 12582912 16777216
# TCP socket send buffer大小。 太小会造成TCP连接throughput降低
net.ipv4.tcp_wmem=4096 12582912 16777216
# 控制每个进程的内存地址空间中 virtual memory area的数量
vm.max_map_count=262144
# 为了支持k8s service, 必须开启
net.ipv4.ip_forward=1
# ubuntu系统上这个参数缺省为"/usr/share/apport/apport %p %s %c %P"。在容器中会造成无法生成core文件
kernel.core_pattern=core
# 内核在发生死锁或者死循环的时候可以触发panic,默认值是0.
kernel.softlockup_panic=0
# 使得iptable可以作用在网桥上
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
# 系统全局PID号数值的限制。
kernel.pid_max=$(( 4 * 1024 * 1024))
# 系统进程描述符总数量限制，根据内存大小动态计算得出，TOTAL_MEM为系统的内存总量，单位是字节，THREAD_SIZE默认为16，单位是kb。
kernel.threads-max=$((TOTAL_MEM / (8 * THREAD_SIZE) ))
# 整个系统fd（包括socket）的总数量限制。根据内存大小动态计算得出，TOTAL_MEM为系统的内存总量，单位是字节，调大该参数避免"Too many open files"错误。
fs.file-max=$(( TOTAL_MEM / 10240 ))
# bcs config end
EOF
    sysctl --system
    # ulimit
    cat > /etc/security/limits.d/99-bcs.conf << EOF
# bcs config begin
*   soft  nproc    1028546
*   hard  nproc    1028546
*   soft  nofile    204800
*   hard  nofile    204800
# bcs config end
EOF
}

_add_hosts () {
    [[ ${MIRROR_IP} != "null" ]] || return 0
    highlight "Add hosts"
    sed -ri.bcs.bak '/bcs config begin for bcs/,/bcs config end for bcs/d' /etc/hosts
    cat >> "/etc/hosts" << EOF
# bcs config begin for bcs
$( 
    if [[ ${ON_CLOUD} == qcloud ]] && [[ -n ${MIRROR_IP} ]]; then 
        echo "${MIRROR_IP} mirrors.tencentyun.com"
    fi
)
# bcs config end for bcs
EOF
}

### 容器运行时: Docker

install_docker () {
    local yum_repo
    yum_repo="${MIRROR_URL}/docker-ce/linux/centos/docker-ce.repo"

    if docker info &>/dev/null && [[ -d ${DOCKER_LIB} ]];then
        warning "Already installed, skipping"
        return 0
    fi
    if ! curl -Ifs "$yum_repo" > /dev/null; then
        error "Unable to curl repository file $yum_repo, is it valid?"
    fi
    curl -fs "$yum_repo" | sed "s#https://download.docker.com#${MIRROR_URL}/docker-ce#g" | tee "$BCS_DIR/docker-ce.repo"
    [[ ! -f /etc/tlinux-release ]] || sed -i "s/\$releasever/7/g" "$BCS_DIR/docker-ce.repo"
    yum install -y -q yum-utils
    yum-config-manager --add-repo "$BCS_DIR/docker-ce.repo"
    yum makecache fast

    # 列出yum源中支持的docker版本
    ## 指定Dokcker版本
    pkg_pattern="$(echo "${DOCKER_VERSION}" | sed "s/-ce-/\\\\.ce.*/g" | sed "s/-/.*/g").*el"
    pkg_version=$(yum list --showduplicates 'docker-ce' | grep "$pkg_pattern" | tail -1 | awk '{print $2}' | cut -d':' -f 2)
    [[ -n $pkg_version ]] || job_fail "ERROR: $DOCKER_VERSION not found amongst yum list results"
    cli_pkg_version=$(yum list --showduplicates 'docker-ce-cli' | grep "$pkg_pattern" | tail -1 | awk '{print $2}' | cut -d':' -f 2)

    # Install
    yum -y install docker-ce-cli-"$cli_pkg_version" docker-ce-"$pkg_version" containerd.io

    # Setting
    render_docker

    # Enable
    systemctl enable docker
    systemctl restart docker

    # Testing
    docker info

    if ! docker --version; then
        error "Did Docker get installed?"
    fi

    if ! docker run --rm "$BK_PUBLIC_REPO"/library/hello-world:latest; then
        error "Could not get docker to run the hello world container"
    fi

}

render_docker () {
    # To-Do Docker配置调优
    # dockerd | Docker Documentation
    # https://docs.docker.com/engine/reference/commandline/dockerd/
    # Docker 调优 | Rancher文档
    # https://docs.rancher.cn/docs/rancher2/best-practices/2.0-2.4/optimize/docker/_index
    # daemon.json
    ## 创建数据目录
    install -dv "${DOCKER_LIB}"
    ## 创建配置文件目录
    install -dv /etc/docker/
    install -dv /etc/systemd/system/docker.service.d/

    if [[ -s /etc/docker/daemon.json ]] && [[ ! -f /etc/docker/daemon.json.bcs.bak ]]; then
        warning "/etc/docker/daemon.json已存在，备份中..."
        cp -av /etc/docker/daemon.json{,.bcs.bak} || job_fail "备份原配置文件失败"
    fi
    log "开始写入配置docker文件..."
    cat > /etc/docker/daemon.json << EOF
{
    "data-root": "${DOCKER_LIB}",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "registry-mirrors": ${REPO_MIRRORS},
    "max-concurrent-downloads": 10,
    "live-restore": ${DOCKER_LIVE_RESTORE},
    "log-level": "info",
    "log-opts": {
        "max-size": "100m",
        "max-file": "5"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ]
}
EOF

    ## 因路由冲突，手动创建Docker网桥
    if [[ ${DOCKER_BRIDGE} != "null" ]]; then
        ip link add name docker0 type bridge
        ip addr add dev docker0 "${DOCKER_BRIDGE}"
        sed -i "/\"data-root\":/i    \"bip\": \"${DOCKER_BRIDGE}\","  /etc/docker/daemon.json
    fi
    
    ## systemd service
    cat>/etc/systemd/system/docker.service.d/bcs-docker.conf<<EOF
[Service]
ExecStartPost=/sbin/iptables -P FORWARD ACCEPT
EOF

    systemctl daemon-reload
    log "Complete"
}

clean_bcsenv () {
    if [[ -f "$BCS_DIR/bcs.env" ]]; then
        if grep -q "bcs config begin" "$BCS_DIR/bcs.env" "$HOME/.bashrc"; then
            sed -ri.bcs.bak "/bcs config begin/,/bcs config end/d" "$BCS_DIR/bcs.env" "$HOME/.bashrc"
        fi
    fi
    log "Complete"
}

### Kubernetes

install_k8stool () {
    local mirror_url
    master_iplist=${BCS_K8S_CTRL_IP:-$LAN_IP}
    read -r -a master_iplist <<< "${master_iplist//,/ }"
    if [[ -z ${master_iplist[0]} ]]; then
        error "BCS_K8S_CTRL_IP is null"
    fi

    highlight "Add kube-apiserver hosts"
    sed -ri.bcs.bak '/bcs config begin for kube-apiserver/,/bcs config end for kube-apiserver/d' /etc/hosts
    cat >> /etc/hosts << EOF
# bcs config begin for kube-apiserver
${master_iplist[0]} k8s-api.bcs.local
# bcs config end for kube-apiserver
EOF
    # Pre
    # 添加repo源
    mirror_url="${MIRROR_URL}/kubernetes"

    cat > "$BCS_DIR/kubernetes.repo" << EOF
[kubernetes]
name=Kubernetes
baseurl=${mirror_url}/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
EOF
    yum install -y -q yum-utils bash-completion
    yum-config-manager --add-repo  "$BCS_DIR/kubernetes.repo"
    yum clean all
    yum makecache fast

    ## kubelet数据目录
    install -dv "${KUBELET_LIB}"

#     cat > /etc/sysconfig/kubelet << EOF
# KUBELET_EXTRA_ARGS="--root-dir=${KUBELET_LIB}"
# EOF

    pkg_pattern="${K8S_VER}"
    pkg_version=$(yum list --showduplicates 'kubeadm' | grep -w "$pkg_pattern" | tail -1 | awk '{print $2}' | cut -d':' -f 2)

    yum -y install \
        "kubectl-${pkg_version}" \
        "kubeadm-${pkg_version}" \
        "kubelet-${pkg_version}"

    # kubeadm config images pull --config="$BCS_DIR/kubeadm-config" -v 11
    # kubeadm config images pull --image-repository="${BK_PUBLIC_REPO}/k8s.gcr.io" \
    #     -v 11 --kubernetes-version "${K8S_VER}" || error "pull kubernetes images failed"

    highlight "kubectl $(kubectl version --client --short || error "Did kubectl get installed?" )"
    highlight "kubeadm Version: $(kubeadm version -o short || error "Did kubectl get installed?" )"
}

install_helm () {
    command -v docker &>/dev/null || error "docker client is not found"
    if ! helm version --short 2>/dev/null | grep -qoE '^v3\.'; then
        docker run -v /usr/bin:/tmp --rm --entrypoint /bin/cp "${BK_PUBLIC_REPO}"/alpine/helm:3.7.2 -f /usr/bin/helm /tmp/ || error "pull helm image failed"
    fi
    highlight "helm Version: $(helm version --short)"
}

get_joincmd () {
    install_k8sctrl
}

install_k8sctrl () {
    local node_name
    local join_cmd
    local cert_key
    local master_join_cmd

    if ! kubectl cluster-info 2>/dev/null ; then
        systemctl enable --now kubelet
        ## etcd数据目录
        install -dv "${ETCD_LIB}"
        ln -sfv "${ETCD_LIB}" /var/lib/

        node_name="master-$(echo "$LAN_IP" | tr '.' '-')"
        highlight "Setup K8S Control Plane: $node_name"

        kubeadm init --config="$BCS_DIR/kubeadm-config" "$( [[ $K8S_VER =~ ^1.12 ]] && echo --ignore-preflight-errors=SystemVerification || echo --upload-certs)" || error "install k8s master failed"
        # kubeadm init --node-name "$node_name" --kubernetes-version "${K8S_VER}" \
        #             --control-plane-endpoint k8s-api.bcs.local \
        #             --image-repository="${BK_PUBLIC_REPO}/k8s.gcr.io" \
        #             --service-cidr="${K8S_SVC_CIDR}" --pod-network-cidr="${K8S_POD_CIDR}" --upload-certs || error "install k8s master failed" 

        install -dv "$HOME/.kube"
        install -v -m 600 -o "$(id -u)" -g "$(id -g)" /etc/kubernetes/admin.conf "$HOME/.kube/config"
        # flannel CNI创建
        if [[ -n ${K8S_CNI} ]]; then
            "install_${K8S_CNI}"
        else
            install_flannel
        fi
    fi
    install_op
    join_cmd="$(kubeadm token create --print-join-command)"
    if [[ $K8S_VER =~ ^1.12 ]]; then
        join_cmd="$join_cmd --ignore-preflight-errors=SystemVerification"
        kubectl set image deployment/coredns coredns="${BK_PUBLIC_REPO}/k8s.gcr.io/coredns:1.2.6" -n kube-system
        # kubectl get nodes -l kubernetes.io/os || kubectl label node -l node-role.kubernetes.io/master= kubernetes.io/os=linux
        highlight "Kubernetes控制节点启动成功"
    else
        cert_key="$(kubeadm init phase upload-certs --upload-certs | grep -E '[a-z0-9]{64}')"

        [[ -n $cert_key ]] || error "not found certificate key"

        master_join_cmd="$join_cmd --control-plane --certificate-key $cert_key"

        [[ "$BCS_CP_WORKER" == "0" ]] || kubectl taint node -l node-role.kubernetes.io/master= node-role.kubernetes.io/master:NoSchedule-

        # echo "<SOPS_VAR>master_join_cmd:${master_join_cmd}</SOPS_VAR>"
        cluster_env=$( grep -vE "LAN_IP=|^#|^source |^export " "${BCS_DIR}"/bcs.env | base64 -w 0)
        master_join_cmd_b64=$(echo -n "${master_join_cmd}" | base64 -w 0)
        echo "<SOPS_VAR>master_join_cmd:${master_join_cmd}</SOPS_VAR>"
        echo "<SOPS_VAR>cluster_env:${cluster_env}</SOPS_VAR>"
        echo "<SOPS_VAR>master_join_cmd_b64:${master_join_cmd_b64}</SOPS_VAR>"

    fi
    cluster_env=$( grep -vE "LAN_IP=|^#|^source |^export " "${BCS_DIR}"/bcs.env | base64 -w 0)
    join_cmd_b64=$(echo -n "${join_cmd}" | base64 -w 0)
    echo "<SOPS_VAR>join_cmd:${join_cmd}</SOPS_VAR>"
    echo "<SOPS_VAR>cluster_env:${cluster_env}</SOPS_VAR>"
    echo "<SOPS_VAR>join_cmd_b64:${join_cmd_b64}</SOPS_VAR>"
    
    cat <<EOF

======================
$( highlight "Kubernetes控制节点启动成功" )
$( 
    [[ $K8S_VER =~ ^1.12 ]] && exit
    highlight "扩容控制平面执行以下命令"
    echo "set -a"
    echo "cluster_env=${cluster_env}"
    echo "master_join_cmd_b64=${master_join_cmd_b64}"
    echo "set +a"
    echo "curl -fsSL https://bkopen-1252002024.file.myqcloud.com/ce7/bcs.sh | bash -s -- install k8s-control-plane"
)
$( 
    highlight "扩容节点执行以下命令"
    echo "set -a"
    echo "cluster_env=${cluster_env}"
    echo "join_cmd_b64=${join_cmd_b64}"
    echo "set +a"
    echo "curl -fsSL https://bkopen-1252002024.file.myqcloud.com/ce7/bcs.sh | bash -s -- install k8s-node"
)
EOF
}

install_k8s () {
    if [[ ${cluster_env} == "null" ]]; then
        install_k8s-1st-ctrl
    else
        install_k8s-node
    fi
}

install_k8smaster () {
    install_k8s-1st-ctrl
}

install_k8s-1st-ctrl () {
    install_bcsenv
    install_docker
    install_k8stool
    install_helm
    install_k8sctrl
}

clean_k8snode () {
  clean_k8s-node
}

clean_k8s-node () {
    systemctl disable --now kubelet
    if [[ $K8S_VER =~ ^1.12 ]]; then
        kubeadm reset phase cleanup-node -f
    else
        kubeadm reset phase cleanup-node
    fi
    bak_dir="/data/backup/$(date +%s)"
    install -dv "$bak_dir" || error "create backup dir $bak_dir failed"
    docker ps | grep -qv NAME && docker rm -f "$(docker ps -aq)"
    [[ -d /etc/kubernetes  ]] && mv -v /etc/kubernetes "$bak_dir"/
    [[ -d /var/lib/kubelet ]] && mv -v /var/lib/kubelet "$bak_dir"/
    [[ -d ${KUBELET_LIB}   ]] && mv -v "${KUBELET_LIB}" "$bak_dir"/kubelet
    systemctl disable --now docker
    log "Uninstall docker, kubelet >>> Done"
}

clean_k8smaster () {
    clean_k8s-control-plane
}

clean_k8s-master () {
    clean_k8s-control-plane
}

clean_k8s-control-plane () {
    if [[ $K8S_VER =~ ^1.12 ]]; then
        kubeadm reset phase update-cluster-status -f
        kubeadm reset phase remove-etcd-member -f
    else
        kubeadm reset phase update-cluster-status
        kubeadm reset phase remove-etcd-member
    fi
    clean_k8snode
    [[ -d "$HOME"/.kube    ]] && mv -v "$HOME"/.kube "$bak_dir"/
    [[ -d ${ETCD_LIB}      ]] && mv -v "${ETCD_LIB}" "$bak_dir"/
    [[ -L /var/lib/etcd    ]] && rm -vf /var/lib/etcd
    [[ -d /var/lib/etcd    ]] && mv -v /var/lib/etcd "$bak_dir"/
    log "Uninstall Kubernetes Control Plane >>> Done"
}

install_k8snode (){
    install_k8s-node
}

install_k8s-control-plane () {
    install_k8s-node
}

install_k8s-node () {
    local join_cmd
    local node_name
    [[ ${cluster_env} != "null" ]] || error "cluster_env未指定 请运行完整的执行命令"
    install_bcsenv
    install_docker

    # 参数检查
    if [[ -z ${BCS_K8S_CTRL_IP} ]]; then
        error "Kubernetes控制平面IP未指定"
    elif [[ ${BCS_K8S_CTRL_IP} == "${LAN_IP}" ]]; then
        error "该节点为Kubernetes第一台控制平面，请至其它节点执行该命令"
    fi
    if [[ ${join_cmd_b64} != "null" ]] && [[ ${master_join_cmd_b64} == "null" ]]; then
        join_cmd="$(echo -n "${join_cmd_b64}" | base64 -d)"
        echo -n "${join_cmd}" | grep -q "kubeadm join" || error "添加节点命令参数异常"
        node_name="node-$(echo "$LAN_IP" | tr '.' '-')"
    elif [[ ${master_join_cmd_b64} != "null" ]]; then
        join_cmd="$(echo -n "${master_join_cmd_b64}" | base64 -d)"
        echo -n "${join_cmd}" | grep -q "kubeadm join" || error "master扩容命令参数异常"
        node_name="master-$(echo "$LAN_IP" | tr '.' '-')"
    else
        error "添加参数有误"
    fi
    install_localpv_dir
    if ! kubectl cluster-info 2>/dev/null && ! docker ps | grep -q pause; then
        install_k8stool
        systemctl enable --now kubelet
        ## etcd数据目录
        install -dv "${ETCD_LIB}"
        ln -sfv "${ETCD_LIB}" /var/lib/
        
        cat "$BCS_DIR/kubeadm-config"

        highlight "$node_name: kubeadm join --config=$BCS_DIR/kubeadm-config -v 11"
        kubeadm join --config="$BCS_DIR/kubeadm-config" -v 11
        
        if [[ ${master_join_cmd_b64} != "null" ]]; then
            install -dv "$HOME/.kube"
            install -v -m 600 -o "$(id -u)" -g "$(id -g)" /etc/kubernetes/admin.conf "$HOME/.kube/config"
            log "Kubernetes Control Plane扩容成功"
            install_op
        else
            log "添加Kubernetes节点成功"
        fi
    fi
}


## CNI

install_flannel () {
    cat << EOF | sed "s#10.244.0.0/16#${K8S_POD_CIDR}#g" | kubectl apply -f -
---
kind: Namespace
apiVersion: v1
metadata:
  name: kube-flannel
  labels:
    pod-security.kubernetes.io/enforce: privileged
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: flannel
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-flannel
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-flannel
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-cfg
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"$([[ $K8S_CNI == "ws_flannel" ]] && echo ', "VNI" : 4096, "Port": 4789' )
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-flannel-ds
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
spec:
  selector:
    matchLabels:
      app: flannel
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
      hostNetwork: true
      priorityClassName: system-node-critical
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni-plugin
       #image: flannelcni/flannel-cni-plugin:v1.1.0 for ppc64le and mips64le (dockerhub limitations may apply)
        image: docker.io/rancher/mirrored-flannelcni-flannel-cni-plugin:v1.1.0
        command:
        - cp
        args:
        - -f
        - /flannel
        - /opt/cni/bin/flannel
        volumeMounts:
        - name: cni-plugin
          mountPath: /opt/cni/bin
      - name: install-cni
       #image: flannelcni/flannel:v0.19.2 for ppc64le and mips64le (dockerhub limitations may apply)
        image: ${BK_PUBLIC_REPO}/flannelcni/flannel:v0.19.2
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
       #image: flannelcni/flannel:v0.19.2 for ppc64le and mips64le (dockerhub limitations may apply)
        image: ${BK_PUBLIC_REPO}/flannelcni/flannel:v0.19.2
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: EVENT_QUEUE_DEPTH
          value: "5000"
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
        - name: xtables-lock
          mountPath: /run/xtables.lock
      volumes:
      - name: run
        hostPath:
          path: /run/flannel
      - name: cni-plugin
        hostPath:
          path: /opt/cni/bin
      - name: cni
        hostPath:
          path: /etc/cni/net.d
      - name: flannel-cfg
        configMap:
          name: kube-flannel-cfg
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
EOF
}


## Windows
install_ws_flannel () {
    if [[ -f /etc/tlinux-release ]]; then
        rmmod vxlan
        lsmod |grep -q vxlan && error "vxlan模块卸载失败"
        modprobe vxlan udp_port=4789
        log "Winodws flannel VXLAN UDP Port using $(cat /sys/module/vxlan/parameters/udp_port)"
    fi
    
    install_flannel
    install_ws_kubeproxy
    install_ws_flannel_overlay
}

install_ws_kubeproxy () {
    cat << 'EOF' | sed "s/VERSION/v${K8S_VER}/g" | kubectl apply -f -
# https://github.com/kubernetes-sigs/sig-windows-tools/releases/latest/download/kube-proxy.yml
apiVersion: v1
data:
  run-script.ps1: |-
    $ErrorActionPreference = "Stop";

    # Get newest cni conf file that is not 0-containerd-nat.json or spin until one shows up.
    # With Docker the kube-proxy pod should not be scheduled to Windows nodes until host networking is configured.
    # With contianerD host networking is required to schedule any pod including the CNI pods so a basic nat network is
    #  configured. This network should not be used by kube-proxy.
    function Get-NetConfFile {
      while ($true) {
        if (Test-Path /host/etc/cni/net.d/) {
          $files = @()
          $files += Get-ChildItem -Path /host/etc/cni/net.d/ -Exclude "0-containerd-nat.json"

          if ($files.Length -gt 0) {
            $file = (($files | Sort-Object LastWriteTime | Select-Object -Last 1).Name)
            Write-Host "Using CNI conf file: $file"
            return $file
          }
        }

        Write-Host "Waiting for CNI file..."
        Start-Sleep 10
      }
    }

    mkdir -force /host/var/lib/kube-proxy/var/run/secrets/kubernetes.io/serviceaccount
    mkdir -force /host/k/kube-proxy

    cp -force /k/kube-proxy/* /host/k/kube-proxy
    cp -force /var/lib/kube-proxy/* /host/var/lib/kube-proxy
    cp -force /var/run/secrets/kubernetes.io/serviceaccount/* /host/var/lib/kube-proxy/var/run/secrets/kubernetes.io/serviceaccount #FIXME?

    # If live patching kube-proxy, make sure and patch it inside this container, so that the SHA
    # matches that of what is on the host. i.e. uncomment the below line...
    # wget <download-path-to-kube-proxy.exe> -outfile k/kube-proxy/kube-proxy.exe
    cp -force /k/kube-proxy/* /host/k/kube-proxy

    $cniConfFile = Get-NetConfFile
    $networkName = (Get-Content "/host/etc/cni/net.d/$cniConfFile" | ConvertFrom-Json).name
    $sourceVip = ($env:POD_IP -split "\.")[0..2] + 0 -join "."
    yq w -i /host/var/lib/kube-proxy/config.conf winkernel.sourceVip $sourceVip
    yq w -i /host/var/lib/kube-proxy/config.conf winkernel.networkName $networkName
    yq w -i /host/var/lib/kube-proxy/config.conf featureGates.WinOverlay true
    yq w -i /host/var/lib/kube-proxy/config.conf mode "kernelspace"
    
    # Start the kube-proxy as a wins process on the host.
    # Note that this will rename kube-proxy.exe to rancher-wins-kube-proxy.exe on the host!
    wins cli process run --path /k/kube-proxy/kube-proxy.exe --args "--v=6 --config=/var/lib/kube-proxy/config.conf --hostname-override=$env:NODE_NAME --feature-gates=WinOverlay=true"

kind: ConfigMap
apiVersion: v1
metadata:
  labels:
    app: kube-proxy
  name: kube-proxy-windows
  namespace: kube-system
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    k8s-app: kube-proxy
  name: kube-proxy-windows
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy-windows
  template:
    metadata:
      labels:
        k8s-app: kube-proxy-windows
    spec:
      serviceAccountName: kube-proxy
      containers:
      - command:
        - pwsh
        args:
        - -file
        - /var/lib/kube-proxy-windows/run-script.ps1
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.nodeName
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        image: sigwindowstools/kube-proxy:VERSION-nanoserver
        name: kube-proxy
        volumeMounts:
        - name: host
          mountPath: /host
        - name: wins
          mountPath: \\.\pipe\rancher_wins
        - mountPath: /var/lib/kube-proxy
          name: kube-proxy
        - mountPath: /var/lib/kube-proxy-windows
          name: kube-proxy-windows
      nodeSelector:
        kubernetes.io/os: windows
      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - operator: Exists
      volumes:
      - configMap:
          defaultMode: 420
          name: kube-proxy-windows
        name: kube-proxy-windows
      - configMap:
          name: kube-proxy
        name: kube-proxy
      - hostPath:
          path: /
        name: host
      - name: wins
        hostPath:
          path: \\.\pipe\rancher_wins
          type: null
  updateStrategy:
    type: RollingUpdate
EOF
}

clean_ws_kubeproxy () {
    kubectl delete -n kube-system daemonset.apps/kube-proxy-windows
    kubectl delete -n kube-system configmap/kube-proxy-windows
}

install_ws_flannel_overlay () {
    cat << 'EOF' | kubectl apply -f -
# https://github.com/kubernetes-sigs/sig-windows-tools/releases/latest/download/flannel-overlay.yml
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-windows-cfg
  namespace: kube-system
  labels:
    tier: node
    app: flannel
data:
  run.ps1: |
    $ErrorActionPreference = "Stop";

    mkdir -force /host/etc/cni/net.d
    mkdir -force /host/etc/kube-flannel
    mkdir -force /host/opt/cni/bin
    mkdir -force /host/k/flannel
    mkdir -force /host/k/flannel/var/run/secrets/kubernetes.io/serviceaccount

    $containerRuntime = "docker"
    if (Test-Path /host/etc/cni/net.d/0-containerd-nat.json) {
      $containerRuntime = "containerd"
    }

    Write-Host "Configuring CNI for $containerRuntime"

    $serviceSubnet = yq r /etc/kubeadm-config/ClusterConfiguration networking.serviceSubnet
    $podSubnet = yq r /etc/kubeadm-config/ClusterConfiguration networking.podSubnet
    $networkJson = wins cli net get | convertfrom-json

    if ($containerRuntime -eq "docker") {
      $cniJson = get-content /etc/kube-flannel-windows/cni-conf.json | ConvertFrom-Json

      $cniJson.delegate.policies[0].Value.ExceptionList = $serviceSubnet, $podSubnet
      $cniJson.delegate.policies[1].Value.DestinationPrefix = $serviceSubnet

      Set-Content -Path /host/etc/cni/net.d/10-flannel.conf ($cniJson | ConvertTo-Json -depth 100)
    } elseif ($containerRuntime -eq "containerd") {
      $cniJson = get-content /etc/kube-flannel-windows/cni-conf-containerd.json | ConvertFrom-Json

      $cniJson.delegate.AdditionalArgs[0].Value.Settings.Exceptions = $serviceSubnet, $podSubnet
      $cniJson.delegate.AdditionalArgs[1].Value.Settings.DestinationPrefix = $serviceSubnet
      $cniJson.delegate.AdditionalArgs[2].Value.Settings.ProviderAddress = $networkJson.AddressCIDR.Split('/')[0]

      Set-Content -Path /host/etc/cni/net.d/10-flannel.conf ($cniJson | ConvertTo-Json -depth 100)
    }

    cp -force /etc/kube-flannel/net-conf.json /host/etc/kube-flannel
    cp -force -recurse /cni/* /host/opt/cni/bin
    cp -force /k/flannel/* /host/k/flannel/
    cp -force /kube-proxy/kubeconfig.conf /host/k/flannel/kubeconfig.yml
    cp -force /var/run/secrets/kubernetes.io/serviceaccount/* /host/k/flannel/var/run/secrets/kubernetes.io/serviceaccount/

    wins cli process run --path /k/flannel/setup.exe --args "--mode=overlay --interface=Ethernet"
    wins cli route add --addresses 169.254.169.254
    wins cli process run --path /k/flannel/flanneld.exe --args "--kube-subnet-mgr --kubeconfig-file /k/flannel/kubeconfig.yml" --envs "POD_NAME=$env:POD_NAME POD_NAMESPACE=$env:POD_NAMESPACE"
  cni-conf.json: |
    {
      "name": "flannel.4096",
      "cniVersion": "0.3.0",
      "type": "flannel",
      "capabilities": {
        "dns": true
      },
      "delegate": {
        "type": "win-overlay",
        "policies": [
          {
            "Name": "EndpointPolicy",
            "Value": {
              "Type": "OutBoundNAT",
              "ExceptionList": []
            }
          },
          {
            "Name": "EndpointPolicy",
            "Value": {
              "Type": "ROUTE",
              "DestinationPrefix": "",
              "NeedEncap": true
            }
          }
        ]
      }
    }
  cni-conf-containerd.json: |
    {
      "name": "flannel.4096",
      "cniVersion": "0.2.0",
      "type": "flannel",
      "capabilities": {
        "portMappings": true,
        "dns": true
      },
      "delegate": {
        "type": "sdnoverlay",
        "AdditionalArgs": [
          {
            "Name": "EndpointPolicy",
            "Value": {
              "Type": "OutBoundNAT",
              "Settings" : {
                "Exceptions": []
              }
            }
          },
          {
            "Name": "EndpointPolicy",
            "Value": {
              "Type": "SDNROUTE",
              "Settings": {
                "DestinationPrefix": "",
                "NeedEncap": true
              }
            }
          },
          {
            "Name":"EndpointPolicy",
            "Value":{
              "Type":"ProviderAddress",
                "Settings":{
                    "ProviderAddress":""
              }
            }
          }
        ]
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-flannel-ds-windows-amd64
  labels:
    tier: node
    app: flannel
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: flannel
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/os
                    operator: In
                    values:
                      - windows
                  - key: kubernetes.io/arch
                    operator: In
                    values:
                      - amd64
      hostNetwork: true
      serviceAccountName: flannel
      tolerations:
      - operator: Exists
        effect: NoSchedule
      containers:
      - name: kube-flannel
        image: sigwindowstools/flannel:v0.13.0-nanoserver
        command:
        - pwsh
        args:
        - -file
        - /etc/kube-flannel-windows/run.ps1
        volumeMounts:
        - name: wins
          mountPath: \\.\pipe\rancher_wins
        - name: host
          mountPath: /host
        - name: kube-proxy
          mountPath: /kube-proxy
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
        - name: flannel-windows-cfg
          mountPath: /etc/kube-flannel-windows/
        - name: kubeadm-config
          mountPath: /etc/kubeadm-config/
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
      volumes:
      - name: opt
        hostPath:
          path: /opt
      - name: host
        hostPath:
          path: /
      - name: cni
        hostPath:
          path: /etc
      - name: flannel-cfg
        configMap:
          name: kube-flannel-cfg
      - name: flannel-windows-cfg
        configMap:
          name: kube-flannel-windows-cfg
      - name: kube-proxy
        configMap:
          name: kube-proxy
      - name: kubeadm-config
        configMap:
          name: kubeadm-config
      - name: wins
        hostPath:
          path: \\.\pipe\rancher_wins
          type: null

EOF
}

clean_ws_flannel_overlay () {
    kubectl delete -n kube-system daemonset.apps/kube-flannel-ds-windows-amd64
    kubectl delete -n kube-system configmap/kube-flannel-windows-cfg
}

### BCS

_init_bk_ns () {
  kubectl create ns bk-system
  kubectl patch ns bk-system --type=json -p='[{"op": "add", "path": "/metadata/labels", "value": {"bcs-webhook": "false"}}]'
}

### Kubernetes生态工具

# k8s >= 1.18
install_ingress-nginx () {
  local NAMESPACE="bk-system"
  kubectl get ns "$NAMESPACE" || _init_bk_ns
  helm repo add mirrors https://hub.bktencent.com/chartrepo/mirrors
  helm repo update
  cat << EOF | helm upgrade --install ingress-nginx mirrors/ingress-nginx -n $NAMESPACE --version 3.36.0 --debug -f - || error "helm upgrade failed"
controller:
  metrics:
    enabled: true
  image:
    registry: ${BK_PUBLIC_REPO}/k8s.gcr.io
    tag: "v0.49.0"
    digest: ""
  config:
    # nginx 与 client 保持的一个长连接能处理的请求数量，默认 100，高并发场景建议调高。
    # 参考: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#keep-alive-requests
    keep-alive-requests: "10000"
    # nginx 与 upstream 保持长连接的最大空闲连接数 (不是最大连接数)，默认 32，在高并发下场景下调大，避免频繁建连导致 TIME_WAIT 飙升。
    # 参考: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#upstream-keepalive-connections
    upstream-keepalive-connections: "200"
    # 每个 worker 进程可以打开的最大连接数，默认 16384。
    # 参考: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#max-worker-connections
    max-worker-connections: "65536"
    # 上传文件需要
    proxy-body-size: "2G"
    proxy-read-timeout: "600"
  service:
    type: NodePort
    nodePorts:
      http: 32080
      https: 32443
  ingressClassResource:
      enabled: true
      default: true
  admissionWebhooks:
    patch:
      image:
        registry: ${BK_PUBLIC_REPO}
        tag: "v1.5.1"
        digest: ""
EOF
  kubectl -n $NAMESPACE wait --for=condition=available --timeout=600s deployment --all
  kubectl -n $NAMESPACE get deployments --output name | xargs -I{} kubectl -n $NAMESPACE rollout status --timeout=600s {}
}

install_kubeapps () {
  helm repo add bitnami https://charts.bitnami.com/bitnami
  kubectl create namespace kubeapps
  helm install kubeapps --namespace kubeapps bitnami/kubeapps
}

clean_kubeapps () {
  helm uninstall kubeapps --namespace kubeapps 
}

install_localpv_dir () {
  install -dv /mnt/blueking/vol{01..20} "${BK_HOME}/localpv"/vol{01..20} || error "create dir failed"
  for i in {01..20}; do
    src_dir="${BK_HOME}/localpv/vol$i"
    dst_dir="/mnt/blueking/vol$i"
    if grep -w "$src_dir" /etc/fstab; then
        warning "WARN: /etc/fstab [$src_dir] already exists"
    else
        echo "$src_dir $dst_dir none defaults,bind 0 0" | tee -a /etc/fstab || error "add /etc/fstab failed"
    fi
  done
  # 挂载
  mount -av || error "mount local pv dir failed"
}

install_localpv () {
  local NAMESPACE="bk-system"
  kubectl get ns "$NAMESPACE" || _init_bk_ns
  helm repo add mirrors https://hub.bktencent.com/chartrepo/mirrors
  helm repo update
  cat << EOF | helm upgrade --install provisioner mirrors/provisioner -n $NAMESPACE --version 2.4.0 --debug -f - || error "helm upgrade failed"
daemonset:
  image: ${BK_PUBLIC_REPO}/k8s.gcr.io/sig-storage/local-volume-provisioner:v2.4.0
classes:
- name: local-storage
  hostDir: /mnt/blueking
  volumeMode: Filesystem
  storageClass: 
    # create and set storage class as default
    isDefaultClass: true
    reclaimPolicy: Delete
EOF
  kubectl -n $NAMESPACE get daemonset --output name | xargs -I{} kubectl -n $NAMESPACE rollout status --timeout=600s {}
}

install_metrics-server () {
  cat << EOF | kubectl apply -f - || error "install metrics-server failed"
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    k8s-app: metrics-server
    rbac.authorization.k8s.io/aggregate-to-admin: "true"
    rbac.authorization.k8s.io/aggregate-to-edit: "true"
    rbac.authorization.k8s.io/aggregate-to-view: "true"
  name: system:aggregated-metrics-reader
rules:
- apiGroups:
  - metrics.k8s.io
  resources:
  - pods
  - nodes
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    k8s-app: metrics-server
  name: system:metrics-server
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - nodes
  - nodes/stats
  - namespaces
  - configmaps
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server-auth-reader
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server:system:auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: system:metrics-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:metrics-server
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
spec:
  ports:
  - name: https
    port: 443
    protocol: TCP
    targetPort: https
  selector:
    k8s-app: metrics-server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: metrics-server
  strategy:
    rollingUpdate:
      maxUnavailable: 0
  template:
    metadata:
      labels:
        k8s-app: metrics-server
    spec:
      containers:
      - args:
        - --cert-dir=/tmp
        - --secure-port=4443
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
        - --kubelet-insecure-tls=true
        image: ${BK_PUBLIC_REPO}/k8s.gcr.io/metrics-server/metrics-server:v0.5.2
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /livez
            port: https
            scheme: HTTPS
          periodSeconds: 10
        name: metrics-server
        ports:
        - containerPort: 4443
          name: https
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /readyz
            port: https
            scheme: HTTPS
          initialDelaySeconds: 20
          periodSeconds: 10
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
        securityContext:
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
        volumeMounts:
        - mountPath: /tmp
          name: tmp-dir
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-cluster-critical
      serviceAccountName: metrics-server
      volumes:
      - emptyDir: {}
        name: tmp-dir
---
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  labels:
    k8s-app: metrics-server
  name: v1beta1.metrics.k8s.io
spec:
  group: metrics.k8s.io
  groupPriorityMinimum: 100
  insecureSkipTLSVerify: true
  service:
    name: metrics-server
    namespace: kube-system
  version: v1beta1
  versionPriority: 100
EOF
  kubectl -n kube-system rollout status --timeout=600s deployment/metrics-server
}

clean_metrics-server () {
  kubectl -n kube-system delete apiservice,deployment,service,clusterrolebinding,rolebinding,clusterrole,serviceaccount -l k8s-app=metrics-server || error "uninstall metrics-server failed"
}

## 脚本框架

check_args () {
    if [[ -n $1 ]]; then
        return 0
    else
        error "缺少参数值"
        usage_and_exit 1
    fi
}

check_func () {
    local OP_TYPE="$1"
    local PROJECT="$2"
    if [[ -n ${OP_TYPE} ]] && [[ -n ${PROJECT} ]]; then
        type "${OP_TYPE}_${PROJECT}" &>/dev/null || error "${OP_TYPE} [$PROJECT] NOT SUPPORT"
    else
        return 0
    fi
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        --install |  -i  | install )
            shift
            PROJECT="$1"
            OP_TYPE="install"
            ;;
        --get | get )
            shift
            PROJECT="$1"
            OP_TYPE="get"
            ;;     
        --clean | -c | clean )
            shift
            PROJECT="$1"
            OP_TYPE="clean"
            ;;
        --render | -r | render )
            shift
            PROJECT="$1"
            OP_TYPE="render"
            ;;
        --help | -h | '-?' | help )
            usage_and_exit 0
            ;;
        --version | -v | -V | version )
            version 
            exit 0
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

check_func "${OP_TYPE}" "${PROJECT}"
[[ ${PROJECT} == "bcsenv" ]] || _on_cloud

case "${OP_TYPE}" in
    install)
        highlight "INSTALL: ${PROJECT}"
        "install_${PROJECT}"
        ok_bcs
        ;;
    get)
        highlight "Get: ${PROJECT}"
        "get_${PROJECT}"
        ok_bcs
        ;;
    clean)
        highlight "CLEAN: ${PROJECT}"
        "clean_${PROJECT}"
        bye_bcs
        ;;
    render)
        highlight "RENDER CONFIG TEMPLATE: ${PROJECT}"
        "render_${PROJECT}"
        ok_bcs
        ;;
    -*)
        error "不可识别的参数: $1"
        ;;
    *) 
        usage_and_exit 0
esac
