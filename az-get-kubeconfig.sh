#!/bin/bash

AKS_CLUSTER_NAME=$1

resource_group=`az aks list | jq -r ".[] | select(.name==\"$AKS_CLUSTER_NAME\") | .resourceGroup"`
export KUBECONFIG=kubeconfigs/$AKS_CLUSTER_NAME
az aks get-credentials --admin --name $AKS_CLUSTER_NAME --resource-group $resource_group