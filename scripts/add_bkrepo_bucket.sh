#!/usr/bin/env bash

SELF_DIR=$(readlink -f $(dirname $0))
ENV_DIR=${SELF_DIR}/../environments/default

if [[ -e "$ENV_DIR"/custom.yaml ]]; then
    MERGED_VALUE=$(yq eval-all '. as $item ireduce ({}; . * $item)' "$ENV_DIR"/values.yaml "$ENV_DIR"/custom.yaml)
else
    MERGED_VALUE=$(< "$ENV_DIR"/values.yaml)
fi

read BKREPO_ADMIN_USER BKREPO_ADMIN_PASSWORD < <(echo "$MERGED_VALUE" | yq e '[.bkrepo.common.username,.bkrepo.common.password] | @tsv' -)
PROJECT_ID=blueking

if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <repo_url> <repo_name> <repo_user> <repo_password> [<is_repo_public>]"
    exit 1
fi

BKREPO_URL=$1
REPO_NAME=$2
REPO_USER=$3
REPO_PASSWORD=$4
REPO_PUBLIC=${5:-false}

CURL="curl -s -u $BKREPO_ADMIN_USER:$BKREPO_ADMIN_PASSWORD"
if $CURL "$BKREPO_URL/repository/api/project/list" | jq -r  .data[].name | grep -qw "$PROJECT_ID"; then
    if ! [[ $($CURL "$BKREPO_URL/repository/api/repo/exist/$PROJECT_ID/$REPO_NAME" | jq -r .data) = "true" ]]; then
        # 如果$REPO_NAME仓库不存在，则创建
        REPO_BODY=$(jq --null-input \
            --arg projectid "$PROJECT_ID" \
            --arg name "$REPO_NAME" \
            --arg public "$REPO_PUBLIC" \
            '{"projectId": $projectid, "name": $name, "type": "GENERIC", "public": $public}')
        RESP=$($CURL "$BKREPO_URL/repository/api/repo/create" \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            -d "${REPO_BODY}")
        if [[ $( jq -r .code <<<"$RESP") -eq 0 ]]; then
            echo "在 $PROJECT_ID 项目下创建仓库 <$REPO_NAME> 成功"
        else
            echo "在 $PROJECT_ID 项目下创建仓库 <$REPO_NAME> 失败"
            echo response: $(jq -c <<<"$RESP")
            exit 2
        fi
    else
        echo "$PROJECT_ID 项目下仓库 <$REPO_NAME> 已存在"
    fi
else
    echo "bkrepo没有 $PROJECT_ID 项目，请检查bkrepo安装是否正确"
    exit 1
fi

# 创建用户到仓库
USER_BODY=$(jq --null-input \
    --arg user "$REPO_USER" \
    --arg pwd "$REPO_PASSWORD" \
    --arg projectid "$PROJECT_ID" \
    --arg reponame "$REPO_NAME" \
    '{"name": $user,"pwd": $pwd, "userId": $user, "projectId": $projectid, "repoName": $reponame}'
)
RESP=$($CURL "$BKREPO_URL/auth/api/user/create/repo" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "${USER_BODY}")

if [[ $( jq -r .code <<<"$RESP") -eq 0 ]]; then
    echo "创建账户 $REPO_USER 成功"
else
    echo "创建账户 $REPO_USER 失败"
    echo response: $(jq -c <<<"$RESP")
    exit 3
fi

