#!/bin/bash

# this script is for SRE engineer to approve the import of a cluster 
# need to run with ACM administrator privilege

CLUSTER_NAME=$1

available=`kubectl get managedcluster $CLUSTER_NAME -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}'`
if [ $? != 0 ]; then
    echo "ERROR: ManagedCluster $CLUSTER_NAME does not exist"
    exit 1
fi

if [ "$available" = "True" ]; then
    echo "ManagedCluster $CLUSTER_NAME is already Available"
    exit 0
fi

echo "== approving cluster join for $CLUSTER_NAME =="
kubectl patch managedcluster --type=merge $CLUSTER_NAME --patch='{"spec":{"hubAcceptsClient":true}}'

# wait for and approve CSR
for i in `seq 1 20`; do 
    csr_list=`kubectl get csr -l "open-cluster-management.io/cluster-name=$CLUSTER_NAME,!open-cluster-management.io/addon-name" -o name | grep $CLUSTER_NAME`

    if [ $? != 0 ]; then
        sleep 5
        continue
    fi

    for csr in `echo $csr_list`; do
        echo "== approving $csr =="
        kubectl certificate approve `kubectl get $csr -o jsonpath='{.metadata.name}'`
    done
   
    break
done