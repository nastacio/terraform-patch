#!/bin/sh

set -x

: "${quay_hostname:=${1}}"
: "${registry_user:=${2}}"
: "${registry_pwd:=${3}}"

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
    && echo "INFO: Installing Quay on ${quay_hostname}" \
    && ${ir_install_path}/mirror-registry --version | grep version \
    && ${ir_install_path}/mirror-registry install \
            --initUser "${registry_user}" \
            --initPassword "${registry_pwd}" \
            --quayHostname "${quay_hostname}" \
            --quayRoot "${quay_root_dir}" \
    && echo "INFO: Quay installation was successful." \
    && podman login --authfile "${mirror_pull_secret}" \
        -u "${registry_user}" \
        -p "${registry_pwd}" \
        "${quay_url}" \
        --tls-verify=false \
    || result=1

    if [ ${result} -eq 1 ]; then
        echo "ERROR: Installation of mirror-registry is not working"
        return ${result}
    fi
}


#
#
#
install_podman \
&& create_quay \
|| exit $?
