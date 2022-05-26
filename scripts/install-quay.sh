#!/bin/sh

set -x

: "${quay_hostname:=${1}}"
: "${registry_user:=${2}}"
: "${registry_pwd:=${3}}"
: "${rhel_pull_secret:=${4}}"

: "${quay_url:=localhost:8443}"


#
#
#
function install_podman() {
    dnf install -y @container-tools \
    && podman version \
    || return 1
}


#
#
#
function create_quay() {
    result=0

    ir_install_path=/data/quay/install
    quay_root_dir=/data/quay/images

    running_status=0
    mirror_pull_secret=pull-secret.txt \
    && podman login --authfile "${mirror_pull_secret}" \
        -u "${registry_user}" \
        -p "${registry_pwd}" \
        "${quay_url}" \
        --tls-verify=false \
    || running_status=1

    if [ "${running_status}" -eq 0 ]; then
        echo "INFO: Running status = ${running_status}"
        return
    fi

    mkdir -p "${ir_install_path}" \
    && if [ ! -f "${ir_install_path}/mirror-registry" ]; then
            curl -sL "https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz" | tar zxf - -C "${ir_install_path}"
        fi \
    && mkdir -p "${quay_root_dir}" \
    && echo "${quay_hostname}" \
    && ${ir_install_path}/mirror-registry --version | grep version \
    && ${ir_install_path}/mirror-registry install \
            --initUser "${registry_user}" \
            --initPassword "${registry_pwd}" \
            --quayHostname "${quay_hostname}" \
            --quayRoot "${quay_root_dir}" \
    &&
    podman login --authfile "${mirror_pull_secret}" \
        -u "${registry_user}" \
        -p "${registry_pwd}" \
        "${quay_url}" \
        --tls-verify=false \
    || result=1

    if [ ${result} -eq 1 ]; then
        echo "ERROR: Installation of mirror-registry is not working"
        return ${result}
    fi

    # https://access.redhat.com/documentation/en-us/openshift_container_platform/4.10/html-single/installing/index#installing-mirroring-creating-registry
    export OCP_RELEASE=4.10.11
    export LOCAL_REGISTRY="${quay_hostname}"
    export LOCAL_REPOSITORY=ocp4/openshift4
    export PRODUCT_REPO=openshift-release-dev
    # https://console.redhat.com/openshift/install/pull-secret
    export LOCAL_SECRET_JSON=mirror-registry.conf
    export RELEASE_NAME="ocp-release"
    export ARCHITECTURE=x86_64
    quay_images_dir="${quay_root_dir}/removable" \
    && mkdir -p "${quay_images_dir}" \
    && export REMOVABLE_MEDIA_PATH="${quay_images_dir}" \
    && echo "${rhel_pull_secret}" > /tmp/a.txt \
    && echo "${rhel_pull_secret}" | sed "s|'|\"|g" | jq ".auths += $(cat "${mirror_pull_secret}").auths" > "${LOCAL_SECRET_JSON}" \
    && chmod 600 "${LOCAL_SECRET_JSON}" \
    && oc adm release mirror -a ${LOCAL_SECRET_JSON}  \
        --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
         --to="${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}" \
         --to-release-image="${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE}" \
         --dry-run \
     && oc adm release mirror \
            -a ${LOCAL_SECRET_JSON} \
            --to-dir=${REMOVABLE_MEDIA_PATH}/mirror quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
    || result=1

    return ${result}
}

install_podman \
&& create_quay \
|| exit $?
