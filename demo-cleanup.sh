#!/bin/bash

for kubeconfig in `ls kubeconfigs/*`; do
    cluster_name=`basename $kubeconfig`
    kubectl delete managedcluster $cluster_name
    kubectl delete csr -l "open-cluster-management.io/cluster-name=$cluster_name"
done