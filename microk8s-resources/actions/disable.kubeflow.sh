#!/usr/bin/env bash

set -eu

source $SNAP/actions/common/utils.sh


CONTROLLER="uk8s"
MODEL="kubeflow"

echo "Removing Kubeflow"
"$SNAP/microk8s-juju.wrapper" destroy-controller $CONTROLLER --destroy-all-models --destroy-storage || true
"$SNAP/microk8s-kubectl.wrapper" delete -n $MODEL -f "${SNAP}/actions/kubeflow" || true
