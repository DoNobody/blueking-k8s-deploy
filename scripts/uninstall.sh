#!/bin/bash

NAMESPACE=${NAMESPACE:-blueking}
release=( $(helm list -n "$NAMESPACE" | awk 'NR>1 && /bk-/ { print $1 }') )


if [[ $1 = "-y" ]] && [[ -z $2 ]]; then
  context=$(kubectl config current-context)
  echo "will uninstall following release @ $context:"
  # print
  printf "%s\n" "${release[@]}" 

  # uninstall release
  helm uninstall -n "$NAMESPACE" "${release[@]}"
  # delete resource by labels
  printf "%s\n" "${release[@]}" | xargs -n1 -I{} kubectl delete deploy,sts,cronjob,job,pod,svc,ingress,secret,cm,sa,role,rolebinding,pvc -n "$NAMESPACE" -l app.kubernetes.io/instance={}
elif [[ $1 = "-y" ]] && [[ -n $2 ]]; then
  if helm list -a -n "$NAMESPACE" | grep -qw "$2"; then 
    context=$(kubectl config current-context)
    echo "will uninstall release ($2) @ $context:"
    # uninstall release
    helm uninstall -n "$NAMESPACE" "$2"
    kubectl delete deploy,sts,cronjob,job,pod,svc,ingress,secret,cm,sa,role,rolebinding,pvc -n "$NAMESPACE" -l app.kubernetes.io/instance="$2"
  else
    echo "can't not found release <$2> @ $NAMESPACE"
    exit 1
  fi
fi
