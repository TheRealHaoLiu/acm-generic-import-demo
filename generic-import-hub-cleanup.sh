#!/bin/bash

IMPORT_NS_NAME='generic-import'

kubectl delete namespace $IMPORT_NS_NAME
kubectl delete clusterrole.rbac.authorization.k8s.io/system:open-cluster-management:managedcluster:bootstrap:generic-import
kubectl delete clusterrolebinding.rbac.authorization.k8s.io/system:open-cluster-management:managedcluster:bootstrap:generic-import

rm configs/*