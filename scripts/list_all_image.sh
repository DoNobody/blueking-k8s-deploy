#!/bin/bash

registry=${1:-hub.bktencent.com}
helmfile -f ../base.yaml.gotmpl --state-values-set imageRegistry=$registry template 2>/dev/null | yq e '..|.image? | select(.)' - | sort -u
helmfile -f ../base-blueking.yaml.gotmpl -l name=bk-nodeman --state-values-set imageRegistry=$registry template 2>/dev/null | yq e '..|.image? | select(.)' - | sort -u
helmfile -f ../monitor.yaml.gotmpl --state-values-set imageRegistry=$registry template 2>/dev/null | yq e '..|.image? | select(.)' - | sort -u
helmfile -f ../03-bcs.yaml.gotmpl --state-values-set global.imageRegistry=$registry template 2>/dev/null | yq e '..|.image? | select(.)' - | sort -u
