#!/usr/bin/env bash

set -eu

source $SNAP/actions/common/utils.sh


CONTROLLER="uk8s"
CLOUD="microk8s"
MODEL="kubeflow"


function print_message () {

cat << EOF

Congratulations, Kubeflow is now available.
Run \`microk8s.kubectl proxy\` to be able to access the dashboard at

    http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/overview?namespace=$MODEL

The central dashboard is available at http://$1/
To tear down Kubeflow and associated infrastructure, run this command:

    microk8s.juju kill-controller $CONTROLLER --destroy-all-models --destroy-storage

For more information, see documentation at:
https://github.com/juju-solutions/bundle-kubeflow/blob/master/README.md

EOF

}


function enable_addons () {
  "$SNAP/microk8s-enable.wrapper" dns storage dashboard juju
  for i in {1..5}
  do
    "$SNAP/microk8s-status.wrapper" --wait-ready --timeout 60 && break || sleep 10
  done
}


function bootstrap_and_deploy () {
  "$SNAP/microk8s-juju.wrapper" bootstrap $CLOUD $CONTROLLER
  "$SNAP/microk8s-juju.wrapper" add-model $MODEL $CLOUD
  # Uncomment this line to present local disks into microk8s as Persistent Volumes
  # microk8s.kubectl create -f storage/local-storage.yml || true
  "$SNAP/microk8s-juju.wrapper" create-storage-pool operator-storage kubernetes storage-class=microk8s-hostpath
  "$SNAP/microk8s-juju.wrapper" deploy kubeflow
  # juju-wait is needed?
  #"$SNAP/microk8s-juju.wrapper" wait -vw

  # General Kubernetes setup
  "$SNAP/microk8s-kubectl.wrapper" create -n $MODEL -f "${SNAP}/actions/kubeflow" || true

  "$SNAP/microk8s-juju.wrapper" config ambassador juju-external-hostname=localhost
  "$SNAP/microk8s-juju.wrapper" expose ambassador
}


echo "Installing Kubeflow"
echo "Enabling required add-ons."
enable_addons
echo "Bootstraping and deploying kubeflow components."
bootstrap_and_deploy
AMBASSADOR_IP=$("$SNAP/microk8s-juju.wrapper" status | grep "ambassador " | awk '{print $8}')
print_message ${AMBASSADOR_IP}
