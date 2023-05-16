#!/bin/bash

#ROLLBACK_REPO_URL=false
#CUR_BK_REPO_URL=$(helm repo list | awk '$1 == "blueking" { print $2}')
CHECK_BK_REPO_URL=${1:-https://hub.bktencent.com/chartrepo/blueking}
#if [[ -n "$CUR_BK_REPO_URL" ]]; then
#    helm repo remove blueking >/dev/null
#    ROLLBACK_REPO_URL=true
#fi

#helm repo add blueking "$CHECK_BK_REPO_URL" >/dev/null

{
helmfile -f ../base.yaml.gotmpl list
helmfile -f ../monitor.yaml.gotmpl list
helmfile -f ../03-bcs.yaml.gotmpl list 2>/dev/null
} | awk '!/^NAME/{print $(NF-1),$NF}' | grep ^blueking | sed 's/^blueking\///'

#if [[ $ROLLBACK_REPO_URL = "true" ]]; then
#    helm repo remove blueking >/dev/null && \
#    helm repo add blueking "$CUR_BK_REPO_URL" >/dev/null
#fi
