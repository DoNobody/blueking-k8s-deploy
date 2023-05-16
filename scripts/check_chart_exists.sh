#!/bin/bash

HELM_REPO_URL=${1:-https://hub.bktencent.com/chartrepo/blueking}
TMP_DIR=$(mktemp -d /tmp/helm_charts_XXXX)
trap 'rm -rf $TMP_DIR' EXIT

xargs -P0 -n2 sh -c 'helm pull --repo '$HELM_REPO_URL' $0 --version $1 -d '$TMP_DIR' 2>/dev/null || echo $0:$1 fail' 
