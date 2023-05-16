#!/bin/bash

export DOCKER_CLI_EXPERIMENTAL=enabled
xargs -n1 -I{} -P0 sh -c 'if ! docker manifest inspect {} &>/dev/null; then echo {} ;fi'
