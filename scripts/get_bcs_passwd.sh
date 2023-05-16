#!/bin/bash
export GATEWAY_TOKEN=$(kubectl get secret --namespace "bcs-system" bcs-password -o jsonpath="{.data.gateway_token}" | base64 --decode)
export MONGODB_PASSWORD=$(kubectl get secret --namespace "bcs-system" bcs-password -o jsonpath="{.data.mongodb_password}" | base64 --decode)
export MESSAGEQUEUE_PASSWORD=$(kubectl get secret --namespace "bcs-system" bcs-password -o jsonpath="{.data.messagequeue_password}" | base64 --decode)
export RABBITMQ_ERLANG_COOKIE=$(kubectl get secret --namespace "bcs-system" bcs-password -o jsonpath="{.data.rabbitmq-erlang-cookie}" | base64 --decode)
export MYSQL_PASSWORD=$(kubectl get secret --namespace "bcs-system" bcs-user-manager-mysql-password -o jsonpath="{.data.mysql-password}" | base64 --decode)
export CLUSTER_MANAGER_PEER_TOKEN=$(kubectl get secret --namespace "bcs-system" bcs-cluster-manager -o jsonpath="{.data.cluster-manager-peer-token}" | base64 --decode)
export REDIS_PASSWORD=$(kubectl get secret --namespace "bcs-system" bcs-redis-password -o jsonpath="{.data.redis-password}" | base64 --decode)
export PRIVATE_KEY=$(kubectl get secret --namespace "bcs-system" bcs-jwt -o jsonpath="{.data.private-key}" | base64 --decode | sed 's/^/      /')
export PUBLIC_KEY=$(kubectl get secret --namespace "bcs-system" bcs-jwt -o jsonpath="{.data.public-key}" | base64 --decode | sed 's/^/      /')
export PUBLIC_KEY_FOR_CHART=$( kubectl get secret --namespace "bcs-system" bcs-jwt -o jsonpath="{.data.public-key}" | base64 --decode | sed 's/^/        /')

cat <<EOF
global:
  env:
    BK_BCS_gatewayToken: "$GATEWAY_TOKEN"
    BK_BCS_jwtPrivateKey: |
$PRIVATE_KEY
    BK_BCS_jwtPublicKey: |
$PUBLIC_KEY
  storage:
    mongodb:
      password: "$MONGODB_PASSWORD"
    messageQueue:
      password: "$MESSAGEQUEUE_PASSWORD"
    redis:
      password: "$REDIS_PASSWORD"
rabbitmq:
  auth:
    erlangCookie: "$RABBITMQ_ERLANG_COOKIE"
bcs-user-manager:
  storage:
    mysql:
      password: "$MYSQL_PASSWORD"
bcs-cluster-manager:
  env:
    BK_BCS_bcsClusterManagerPeerToken: "$CLUSTER_MANAGER_PEER_TOKEN"
bcs-webconsole:
  config:
    bcs_conf:
      jwt_public_key: |
$PUBLIC_KEY_FOR_CHART
      token: "$GATEWAY_TOKEN"
    bcs_env_conf:
      - cluster_env: prod
        host: http://bcs-api-gateway
        token: "$GATEWAY_TOKEN"
EOF
