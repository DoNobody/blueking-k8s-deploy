#!/bin/bash

NAMESPACE=${NAMESPACE:-blueking}
self_dir=$(readlink -f $(dirname $0))
url=$1
database=$2
username=$3
password=$4

cat "${self_dir}/add_mongodb_user.sh" | kubectl exec -i -n "$NAMESPACE" bk-mongodb-0 -- bash -s -- -i "$url" -u "$username"  -p "$password"  -d "$database"
