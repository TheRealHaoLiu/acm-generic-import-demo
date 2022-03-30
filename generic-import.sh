#!/bin/bash

#NOTE: the kubeconfig should be pointed to the managed cluster that you want to import

#TODO: we may be able to detect this from azure kubeconfig?
CLUSTER_NAME=$1

function updateImportYaml {
    ACM_NS=$(oc get multiclusterhub -A -ojsonpath='{.items[0].metadata.namespace}' --kubeconfig=configs/bootstrap-kubeconfig.yaml)
    ACM_VERSION=$(oc get multiclusterhub -A -ojsonpath='{.items[0].status.currentVersion}' --kubeconfig=configs/bootstrap-kubeconfig.yaml)

    REGISTRATION_OPERATOR_IMG=""
    REGISTRATION_IMG=""
    WORK_IMG=""
    # If ACM 2.5.0 or higher, get images from MCE CSV
    if [[ $ACM_VERSION =~ [2-9]\.[5-9]+\.[0-9]+.* ]]; then
        MCE_CSV=$(oc get sub -n multicluster-engine multicluster-engine -ojsonpath='{.status.currentCSV}'  --kubeconfig=configs/bootstrap-kubeconfig.yaml)
        IMGS=$(oc get csv ${MCE_CSV} -n multicluster-engine -ojsonpath='{.spec.install.spec.deployments[0].spec.template.spec.containers[0].env}'  --kubeconfig=configs/bootstrap-kubeconfig.yaml | jq)
        
        REGISTRATION_OPERATOR_IMG=$(echo $IMGS | jq -c '.[] | select(.name | test("^OPERAND_IMAGE_REGISTRATION_OPERATOR$"))' | jq '.value')
        REGISTRATION_IMG=$(echo $IMGS | jq -c '.[] | select(.name | test("^OPERAND_IMAGE_REGISTRATION$"))' | jq '.value')
        WORK_IMG=$(echo $IMGS | jq -c '.[] | select(.name | test("^OPERAND_IMAGE_WORK$"))' | jq '.value')
    else 
        # In ACM lower than 2.5.0, get images from MCH Configmap
        ACM_IMAGES_CM="mch-image-manifest-${ACM_VERSION}"
        REGISTRATION_OPERATOR_IMG=$(oc get configmap -n ${ACM_NS} ${ACM_IMAGES_CM} -ojsonpath='{.data.registration_operator}' --kubeconfig=configs/bootstrap-kubeconfig.yaml)
        REGISTRATION_IMG=$(oc get configmap -n ${ACM_NS} ${ACM_IMAGES_CM} -ojsonpath='{.data.registration}' --kubeconfig=configs/bootstrap-kubeconfig.yaml)
        WORK_IMG=$(oc get configmap -n ${ACM_NS} ${ACM_IMAGES_CM} -ojsonpath='{.data.work}' --kubeconfig=configs/bootstrap-kubeconfig.yaml)
    fi

    if [[ "$REGISTRATION_OPERATOR_IMG" == "" || "$REGISTRATION_IMG" == "" || "$WORK_IMG" == "" ]]; then
        echo "Could not find images for ACM $ACM_VERSION"
        exit 1
    fi

    ## Updates import.yaml w/ correct imagereferences directly
    _DEPLOYMENT_DOC_INDEX=$(yq eval 'select(.kind == "Deployment") | di' templates/import.yaml)
    _KLUSTERLET_DOC_INDEX=$(yq eval 'select(.kind == "Klusterlet") | di' templates/import.yaml)

    _DOC_INDEX=${_DEPLOYMENT_DOC_INDEX} _IMG=${REGISTRATION_OPERATOR_IMG} yq eval -i 'select(di == env(_DOC_INDEX)).spec.template.spec.containers[0].image = env(_IMG)' templates/import.yaml
    _DOC_INDEX=${_KLUSTERLET_DOC_INDEX} _IMG=${REGISTRATION_IMG} yq eval -i 'select(di == env(_DOC_INDEX)).spec.registrationImagePullSpec = env(_IMG)' templates/import.yaml
    _DOC_INDEX=${_KLUSTERLET_DOC_INDEX} _IMG=${WORK_IMG} yq eval -i 'select(di == env(_DOC_INDEX)).spec.workImagePullSpec = env(_IMG)' templates/import.yaml
}

# create ManagedCluster on hub using bootstrap-kubeconfig.yaml
cat templates/managedcluster.yaml | \
    sed s~CLUSTER_NAME~$CLUSTER_NAME~g | \
    kubectl apply --kubeconfig=configs/bootstrap-kubeconfig.yaml -f - 

# create crds on ManagedCluster
cat templates/crds.yaml | \
    kubectl apply -f -

updateImportYaml

# apply import.yaml to ManagedCluster
if [ "$(uname)" == "Darwin" ]; then
  cat templates/import.yaml | \
    sed s~CLUSTER_NAME~$CLUSTER_NAME~g | \
    sed s~BOOTSTRAP_KUBECONFIG_B64~$(cat configs/bootstrap-kubeconfig.yaml | base64)~g | \
    sed s~DOCKER_CONFIG_JSON_B64~$(cat configs/dockerconfig.json.b64)~g | \
    kubectl apply -f -
else
  cat templates/import.yaml | \
    sed s~CLUSTER_NAME~$CLUSTER_NAME~g | \
    sed s~BOOTSTRAP_KUBECONFIG_B64~$(cat configs/bootstrap-kubeconfig.yaml | base64 -w 0)~g | \
    sed s~DOCKER_CONFIG_JSON_B64~$(cat configs/dockerconfig.json.b64)~g | \
    kubectl apply -f -
fi

