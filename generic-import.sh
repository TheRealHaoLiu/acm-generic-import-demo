#!/bin/bash

#NOTE: the kubeconfig should be pointed to the managed cluster that you want to import

#TODO: we may be able to detect this from azure kubeconfig?
CLUSTER_NAME=$1

# create ManagedCluster on hub using bootstrap-kubeconfig.yaml
cat templates/managedcluster.yaml | \
    sed s~CLUSTER_NAME~$CLUSTER_NAME~g | \
    kubectl apply --kubeconfig=configs/bootstrap-kubeconfig.yaml -f - 

# create crds on ManagedCluster
cat templates/crds.yaml | \
    kubectl apply -f -

# apply import.yaml to ManagedCluster
cat templates/import.yaml | \
    sed s~CLUSTER_NAME~$CLUSTER_NAME~g | \
    sed s~BOOTSTRAP_KUBECONFIG_B64~$(cat configs/bootstrap-kubeconfig.yaml | base64 -w 0)~g | \
    sed s~DOCKER_CONFIG_JSON_B64~$(cat configs/dockerconfig.json.b64)~g | \
    kubectl apply -f -
