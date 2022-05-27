#!/bin/sh

set -x

: "${quay_hostname:=${1}}"
: "${registry_user:=${2}}"
: "${registry_pwd:=${3}}"
: "${rhel_pull_secret:=${4}}"

: "${quay_url:=localhost:8443}"

: "${OCP_RELEASE:=4.10.12}"


#
# If the OC CLI is older than 4.5, then installs the latest version
#
function check_install_oc() {
    local install=0

    echo "INFO: Checking OpenShift client installation..." 
    type -p oc > /dev/null 2>&1 || install=1
    if [ ${install} -eq 0 ]; then
        oc_version=$(oc version | grep "Client Version" | cut -d ":" -f 2 | tr -d " ")
        if [ "${oc_version}" == "" ] ||
           [[ ${oc_version} == "3."* ]] ||
           [[ ${oc_version} == "4.1."* ]] ||
           [[ ${oc_version} == "4.2."* ]] ||
           [[ ${oc_version} == "4.3."* ]] ||
           [[ ${oc_version} == "4.4."* ]]; then
            echo "INFO: OpenShift client is older than 4.5." 
            install=1
        fi
    fi

    if [ ${install} -eq 1 ]; then
        echo "INFO: Installing latest OpenShift client..." 
        curl -sL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xzf - -C /usr/bin \
        && echo "INFO: Installed latest OpenShift client." \
        && oc version \
        && install=0
    fi

    if [ ${install} -eq 1 ]; then
        echo "ERROR: Installation of oc CLI failed." \
    fi

    return ${install}
}


#
#
# https://access.redhat.com/documentation/en-us/openshift_container_platform/4.10/html-single/installing/index#installing-mirroring-creating-registry
#
function clone_ocp() {
    result=0

    echo "INFO: Cloning OCP images"
    ir_install_path=/data/quay/install
    quay_root_dir=/data/quay/images

    running_status=0
    mirror_pull_secret=pull-secret.txt \
    && podman login --authfile "${mirror_pull_secret}" \
        -u "${registry_user}" \
        -p "${registry_pwd}" \
        "${quay_url}" \
        --tls-verify=false \

    export LOCAL_REGISTRY="${quay_hostname}"
    export LOCAL_REPOSITORY=ocp4/openshift4
    export PRODUCT_REPO=openshift-release-dev
    # https://console.redhat.com/openshift/install/pull-secret
    export LOCAL_SECRET_JSON=mirror-registry.conf
    export RELEASE_NAME="ocp-release"
    export ARCHITECTURE=x86_64
    mirror_pull_secret=pull-secret.txt \
    && podman login --authfile "${mirror_pull_secret}" \
        -u "${registry_user}" \
        -p "${registry_pwd}" \
        "${quay_url}" \
        --tls-verify=false \
    && quay_images_dir="${quay_root_dir}/removable" \
    && mkdir -p "${quay_images_dir}" \
    && export REMOVABLE_MEDIA_PATH="${quay_images_dir}" \
    && echo "INFO: Generating pull secret." \
    && echo "${rhel_pull_secret}" > /tmp/a.txt \
    && echo "${rhel_pull_secret}" | sed "s|'|\"|g" | jq ".auths += $(cat "${mirror_pull_secret}").auths" > "${LOCAL_SECRET_JSON}" \
    && chmod 600 "${LOCAL_SECRET_JSON}" \
    && cat "${LOCAL_SECRET_JSON}" \
    && echo "INFO: Reviewing images..." \
    && oc adm release mirror -a ${LOCAL_SECRET_JSON}  \
        --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
         --to="${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}" \
         --to-release-image="${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE}" \
         --dry-run \
    && echo "INFO: Mirroring images..." \
    && oc adm release mirror \
            -a ${LOCAL_SECRET_JSON} \
            --to-dir=${REMOVABLE_MEDIA_PATH}/mirror quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
    && echo "INFO: Mirrored images successfully." \
    || result=1

    return ${result}
}

sudo yum install jq -y \
&& check_install_oc \
&& clone_ocp \
|| exit $?
