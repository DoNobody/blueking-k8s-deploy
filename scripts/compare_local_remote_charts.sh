#!/bin/bash

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <blueking helmfile>"
    exit 1
fi

BK_HELMFILE="$1"

echo "run helm repo update first."
helm repo update >/dev/null

# 首先列出helmfile期望的动态版本
while read namespace chart version; do
    s_chart=${chart##*/}
    repo_ver=$(helm search repo "$chart" --version "$version" | awk 'NR == 2 { print $2 }')
    local_ver=$(helm list -n "$namespace" | grep -P "\t${s_chart}(?=-[0-9])" | awk -v name="^${s_chart}" -F '\t' '$6 ~ name { print $6 }')
    local_ver=$(echo "$local_ver" | sed -r -e "s,^${s_chart}-,," -e 's/[[:space:]]+//')
    if ! [[ $repo_ver = $local_ver ]]; then
        printf "%s\t%s\t%s\n"  "$chart" "$local_ver" "$repo_ver"
    fi
done < <( helmfile -f "$BK_HELMFILE" list |  awk -F'\t' '$NF ~ /[~^]/ {print $2,$5,$6}'  )
