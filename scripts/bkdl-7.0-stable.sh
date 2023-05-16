#!/bin/bash
# 下载 bkce7 所需的软件包并制备 bkce7_setup.sh 所需的安装目录.

# 读取下载信息的url, 也会作为前缀和相对路径拼接出完整url.
release_baseurl="${RELEASE_BASEURL:-https://bkopen-1252002024.file.myqcloud.com/}"
# 所有的url均先存储在此目录. 下载中使用.downloading后缀.
cache_dir="${CACHE_DIR:-$HOME/.cache/bkdl}"
# 待制备的安装目录. 会从cache_dir读取文件处理到此目录
install_dir="${INSTALL_DIR:-$HOME/bkhelmfile}"
verbosity=1  # 默认详细级别为1
release_version=  # 默认为空
release_channel_default="ce7/7.0-stable"  # 脚本默认的发行通道.
release_channel=  # 为空
dry_run=0
no_cache=0
patt_semver='v?[0-9]+[.][0-9]+[.][0-9]+([-.+][0-9A-Za-z]+)*'  # semver版本格式.
# terminal colors.
COLOR_RESET=$'\033[0m'
COLOR_REVERSE=$'\033[7m'

# 异常捕获
set -Eu
trap "on_ERR;" ERR
on_ERR (){
  local ret=$? cmd="$BASH_COMMAND" f="${BASH_SOURCE:--}" lino="$BASH_LINENO"
  printf >&2 "ERROR: %s:%s: \033[7m%s\033[0m exit with code %s.\n" "$f" "$lino" "$cmd" "$ret"
  exit "$ret"
}

tip (){ echo >&2 "$@"; }
log_info (){ [ $verbosity -lt 1 ] || tip "$@"; }
log_debug (){ [ $verbosity -lt 2 ] || tip "$@"; }
log_debug2 (){ [ $verbosity -lt 3 ] || tip "$@"; }

# 获取url, 并设置cached_file变量为缓存文件路径.
fetch_url (){
  local url=$1
  if [ "${url: 0:4}" != http ]; then
    url="$release_baseurl$url"
  fi
  local fp dl_f ret
  fp=${url#$release_baseurl}  # 如果以release_baseurl开头, 则取相对目录.
  fp=${fp#http*//*/}   # 否则去掉域名部分.
  cached_file="$cache_dir/$fp"
  dl_f="$cached_file.downloading"
  log_debug "  url=$url, cached_file=$cached_file."
  if [ "$dry_run" -ge 2 ]; then log_info "  TIP: skip download in dry-run mode."; return 0; fi
  curl_args=(${CURL_OPTS:-} --retry 2 -fL --create-dirs)  # 允许环境变量提供参数. set -u要求此数组不能为空.
  if [ -f "$cached_file" ] && [ $no_cache -eq 0 ]; then
    log_debug "  skip download due to cached_file exist."
    return 0
  fi
  log_info "  downloading $url to $cached_file."
  if [ -f "$cached_file" ] && [ $no_cache -eq 1 ]; then curl_args+=(-z "$cached_file"); fi  # 文件提供缓存时间戳
  case $verbosity in
    0) curl_args+=(-sS);;
    1) curl_args+=("-#");;  # 单行bar进度条.
    2) : ;;  # curl 默认的多行进度条.
    3) curl_args+=(-sSvw 'size_download=%{size_download}\n') ;;  # 显示header及实际下载的大小.
  esac
  curl "${curl_args[@]}" -Ro "$dl_f" "$url"  # -R远端时间为缓存关键, 配合-z提供时间戳
  ret=$?
  if [ -f "$dl_f" ]; then mv "$dl_f" "$cached_file"; fi  # 如果下载到了文件且无异常, 则重命名.
  return $ret
}

# 处理url到指定路径.
processor (){
  if ! declare -f "processor_$1" &>/dev/null; then
    tip "ERROR: no such processor: processor_$1."
    return 1
  fi
  mkdir -p "${dst%/*}"  # 如果结尾为/, 则创建所需的目录. dirname会先过滤结尾的/.
  log_info "  $1 $src to $dst."
  if [ "$dry_run" -ge 1 ]; then log_info "  TIP: skip make install dir in dry-run mode." ;return 0; fi
  log_debug2 "  processor=processor_$*."
  "processor_$@"  # 调用"processor_"开头的函数.
  if [ "${pkg_id: -4}" = "_cmd" ]; then chmod +x "$dst"; fi
}
# noop: 无操作.
processor_noop (){ :; }
# copy无参数
processor_copy (){
  cp -a "$src" "$dst"
}
# untar允许参数:
processor_untar (){
  tar xf "$src" "$@" -C "$dst"
}
processor_ungz (){ gzip -dc "$src" > "$dst"; }
processor_unxz (){ xz -dc "$src" > "$dst"; }
processor_unzip (){ unzip -qo "$src" -d "$dst"; }
processor_print (){ cat "$src" > "$dst"; }

# 目前仅遍历列表. 后续加入版本号解析及依赖项选择.
get_packages (){
  tip "make install dir: $COLOR_REVERSE$(realpath "$install_dir")$COLOR_RESET."
  while IFS=$'\t' read -r pkg_id url local_dir processor _; do
    dst="$install_dir/$local_dir"
    log_info "get package $pkg_id."
    fetch_url "$url"
    src="$cached_file"
    processor $processor  # 无引号, 自动展开空格.
  done
}

# 读取cache的index文件, 获取此版本中各软件包的用途及下载路径.
parse_release_file (){
  local names="$*"
  gawk -F"\t" -v OFS="\t" -v verbosity="$verbosity" -v names="$names" '
BEGIN{ stderr="/dev/stderr"; sep="[ ,]"; prog_name="parse_release_file";}
{
  p=$1; desc=$2; deps=$3
  ver=$4;local_dir=$5; processor=$6; fmt_url=$7
  if(NF!=3&&NF!=7){ print "NF is not 3 or 7:", NF, $0 > stderr; next; }
  a_pkg_v[p]=ver;
  split(deps, a, sep)
  for(i=1;i<=length(a);i++){
    rp=a[i]; a_deps[p][rp]=i;
  }
  a_processor[p]=processor
  a_local_dir[p]=local_dir
  a_fmt_url[p]=fmt_url
}
function req_pkg(    p, req_by, depth){
  if(depth>99){ print "depth exeeded.", depth > stderr; exit(6); }
  if(verbosity>1)printf  "%*s%s  %s\n", depth*2, "", p, a_pkg_v[p]?a_pkg_v[p]:"GROUP" > stderr
  if(p in a_req)return 0;
  a_req[p]=depth++
  if(p in a_deps){
    for(rp in a_deps[p]){
      req_pkg(rp, req_by " " rp, depth)
    }
  }
  if(a_pkg_v[p]){
    url=sprintf(a_fmt_url[p], a_pkg_v[p])
    local_dir=a_local_dir[p]
    processor=a_processor[p]
    print p, url, local_dir, processor
  }
}
END{
  split(names, a, sep)
  for(i=1;i<=length(a);i++){
    eq_pos=index(a[i], "=");
    if(eq_pos>0){tv=substr(a[i], eq_pos+1); tp=substr(a[i], 1, eq_pos-1); a[i]=tp; }else{tp=a[i];}
    if(tp in a_pkg_v){
      if(eq_pos>0){
        if(a_pkg_v[tp]){ printf prog_name ": overwrite version for NAME: %s: %s -> %s.\n", tp, a_pkg_v[tp], tv > stderr; a_pkg_v[tp]=tv; }
        else { print prog_name ": ignore version of GROUP NAME: " tp > stderr}
      }}
    else { print prog_name ": ERROR: unknown NAME: " tp > stderr; e++; continue; }
  }
  if(e>0){ exit(14); }
  if(verbosity>1)printf prog_name ": dependency tree of %s.\n", names > stderr
  PROCINFO["sorted_in"]="@val_num_asc"
  for(i=1;i<=length(a);i++){
    req_pkg(a[i], a[i], 1)
  }
}' "$release_file"
}

# 预期取得一个release-file.
get_release_file (){
  case "$release_version" in
    list|latest) log_info "fetch version list.";
      dry_run=0 no_cache=2 fetch_url "$release_channel/list.txt";;&
    latest) release_version=$(tail -1 "$cached_file");
      if [ -z "$release_version" ]; then tip "ERROR: unable to get latest version."; exit 9;fi
      log_debug "keyword latest picked release_version=$release_version.";;
    list) log_info "available versions are:"; cat "$cached_file"; exit 9;;
  esac
  if grep -xPq "$patt_semver" <<< "$release_version"; then
    log_info "fetch release-file of $release_channel/$release_version."
  else
    log_info "WARNING: release_version=$release_version, does not match pattern: $patt_semver."
  fi
  # 拉取release描述文件.
  dry_run=0 fetch_url "$release_channel/$release_version.txt" || {  # dry-run不能阻止拉取release索引文件
    case $? in
      22) log_info "release-file not exist, using option '-r list' to get available versions.";;
      *) log_info "failed to get release-file.";;
    esac
    exit 15
  }
  release_file="$cached_file"
}

# 显示release-file里的NAME列表.
show_release_file (){
  log_info "available NAME in $(realpath "$release_file"):"
  awk -F"\t" -v verbosity="$verbosity" '
    BEGIN{OFS="\t";if(verbosity)print "NAME", "VERSION", "Description"}
    {print $1, $4?$4:"- (GROUP)", $2 ($3?", requires "$3".":".")}
    ' "$release_file" | column -ts $'\t'
}

# 重要参数提醒.
notable_options (){
  if [ "$release_channel" != "$release_channel_default" ]; then
    tip "NOTE: release_channel switched to $release_channel."
  fi
  case "$dry_run" in
    1) tip "OPTION dry_run=1, skip make install dir.";;
    2) tip "OPTION dry_run=2, skip make install dir and downloads.";;
  esac
  case "$no_cache" in
    0) log_debug "OPTION update(-u)=0, download file which not cached.";;
    1) tip "OPTION update=1, download file if cache is out-of-date.";;
    2) tip "OPTION update=2, download files and rebuild caches.";;
  esac
  case "$verbosity" in
    1) : "OPTION verbosity(-v)=1, normal output.";;  # 无需提示 ^_^
    2) tip "OPTION verbosity=2, verbose output.";;
    3) tip "OPTION verbosity=3, debug output.";;
  esac
  log_debug "OPTION cache_dir=$cache_dir, release_baseurl=$release_baseurl."
}
usage="Usage: $0 -r list|latest|VER [OPTION] NAME[=VERSION]...  -- download bkce7 softwares and files.
OPTION:
  -h       show this help message.
  -n       dry run, skip make install_dir, using '-nn' to skip downloads too.
  -q       quiet, suppress normal message.
  -u       update, check update for cached files. using '-uu' to rebuild caches.
  -v       verbose, more message. using '-vv' for more verbosity.
  -B URL   release base URL. the URL prefix of relative path in release-file.
  -C STR   release channel, default to $release_channel_default.
  -c DIR   cache dir, default to $cache_dir.
  -i DIR   install dir, default to $install_dir.
  -r VER   release version, using 'list' to show versions, or 'latest' to select last one.

if no NAME given but -r option is set, will list available NAME in release-file.
if NAME is not a GROUP, you could specify VERSION in the form of NAME=VERSION.
"

if ! getopt -V 2>&1 | grep -q util-linux; then  # 预期getopt来自util-linux.
  echo >&2 "ERROR: unsupported getopt command."
  exit 3
fi
args=$(getopt -n "$0" -s bash hnquvB:C:c:i:r: "$@") || { tip "$usage"; exit 3; }
log_debug2 "args formatted by getopt: $args."
eval set -- "$args"  # getopt -s 配合 eval 处理空字符串参数.
# 处理参数.
while true; do
  case "${1:-}" in
    -h) tip "$usage"; exit 3;;
    -n) ((++dry_run));;
    -q) verbosity=0;;
    -u) ((++no_cache));;
    -v) ((++verbosity));;
    -C) release_channel="$2"; shift;;
    -c) cache_dir="$2"; shift;;
    -i) install_dir="$2"; shift;;
    -r) release_version="$2"; shift;;
    -B) release_baseurl="$2"; shift;;
    --) shift; break;;
    *) tip "$0: ERROR: no option handler for arg: ${1:-}."; exit 3;;
  esac
  shift  # 统一移除1个参数.
done


release_channel="${release_channel:-$release_channel_default}"  # 如果没有修改, 则使用默认值.
if [ -z "$release_version" ]; then
  tip "$usage"; exit 3;
fi
notable_options  # 重要参数提示.
get_release_file
# 解析获得下载列表, 无NAME则提示.
if [ $# -eq 0 ]; then
  log_info "ERROR: no NAME given."
  show_release_file
  exit 8
fi
package_list=$(parse_release_file "$@") || { show_release_file; exit $?; }  # gawk脚本接管报错及提示.
log_debug2 "package_list=$package_list."
if [ -z "$package_list" ]; then tip "no package selected, do nothing."; exit 0; fi
get_packages <<< "$package_list"
log_info "job done."
