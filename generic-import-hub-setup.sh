#!/bin/bash

IMPORT_NS_NAME='generic-import'
IMPORT_SA_NAME='aoc-import'

mkdir -p configs
mkdir -p kubeconfigs

# create generic import serviceaccount
kubectl create namespace $IMPORT_NS_NAME 2> /dev/null 
kubectl create serviceaccount -n $IMPORT_NS_NAME $IMPORT_SA_NAME 2> /dev/null

cat << EOF | kubectl apply -f - 2> /dev/null
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:open-cluster-management:managedcluster:bootstrap:generic-import
rules:
- apiGroups:
  - certificates.k8s.io
  resources:
  - certificatesigningrequests
  verbs:
  - create
  - get
  - list
  - watch
- apiGroups:
  - cluster.open-cluster-management.io
  resources:
  - managedclusters
  verbs:
  - get
  - create
- apiGroups:
  - cluster.open-cluster-management.io
  resources:
  - managedclustersets/join
  verbs:
  - create
- apiGroups:
  - operator.open-cluster-management.io
  resources:
  - multiclusterhubs
  verbs:
  - list
- apiGroups:
  - operators.coreos.com
  resources:
  - subscriptions
  - clusterserviceversions
  verbs:
  - get
  - list
- apiGroups:
  - ''
  resources:
  - configmaps
  verbs:
  - get
EOF

cat << EOF | kubectl apply -f - 2> /dev/null
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:open-cluster-management:managedcluster:bootstrap:generic-import
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:open-cluster-management:managedcluster:bootstrap:generic-import
subjects:
- kind: ServiceAccount
  name: $IMPORT_SA_NAME
  namespace: $IMPORT_NS_NAME
EOF

#TODO: improve this flow with token request rather than direct serviceaccount token
# example:
# curl -X "POST" "https://{kubernetes API IP}:{kubernetes API Port}/api/v1/namespaces/{namespace}/serviceaccounts/{name}/token" \
#      -H 'Authorization: Bearer {your bearer token}' \
#      -H 'Content-Type: application/json; charset=utf-8' \
#      -d $'{}'

# extract serviceaccount token to configs directory
import_sa_secret_name=`kubectl get serviceaccount $IMPORT_SA_NAME -n $IMPORT_NS_NAME -o jsonpath='{.secrets}' \
    | jq -r '[.[] |  select(.name | contains ("token")) | .name] | first '`


if [ "$(uname)" == "Darwin" ]; then
  hub_kubeconfig_json_b64=`kubectl config view --minify --flatten --raw=true -o json  | jq | base64` #note: do not print contain cred
else
  hub_kubeconfig_json_b64=`kubectl config view --minify --flatten --raw=true -o json | jq | base64 -w 0` #note: do not print contain cred
fi
hub_insecure_skip_tls_verify=`echo $hub_kubeconfig_json_b64 | base64 -d | jq -r '.clusters[0].cluster."insecure-skip-tls-verify"'`
# TODO: if CA cert configured for hub-kubeconfig extract CA from hub-kubeconfig

IMPORT_TOKEN=`kubectl get secret $import_sa_secret_name -n $IMPORT_NS_NAME -o jsonpath='{.data.token}' | base64 -d`

# get serviceaccount CA
HUB_CA_DATA_B64=`kubectl get secret $import_sa_secret_name -n $IMPORT_NS_NAME -o jsonpath='{.data.ca\.crt}'`

# TODO: handle customized CA cert or extract CA from hub-kubeconfig

# get hub API server information 
HUB_API_SERVER=`echo $hub_kubeconfig_json_b64 | base64 -d | jq -r '.clusters[0].cluster.server'`

# get pull secret 
kubectl get secret -n openshift-config pull-secret -o jsonpath={.data.\\.dockerconfigjson} > configs/dockerconfig.json.b64

cat templates/bootstrap-kubeconfig.yaml | \
    sed s~HUB_API_SERVER~$HUB_API_SERVER~g | \
    sed s~HUB_CA_DATA_B64~$HUB_CA_DATA_B64~g | \
    sed s~IMPORT_TOKEN~$IMPORT_TOKEN~g > configs/bootstrap-kubeconfig.yaml
