#!/bin/sh

set -x

: "${rhsm_username:=${1}}"
: "${rhsm_password:=${2}}"

#
#
#
function register_rhsm() {
    echo "INFO: Registering the RHEL system."
    subscription_status=$(subscription-manager list | grep "^Status:" | tr -d " " | cut -d ":" -f 2)
    if [ "${subscription_status}" != "Subscribed" ]; then
        subscription-manager register \
            --username "${rhsm_username}" \
            --password "${rhsm_password}" \
            --auto-attach ||
        {
            echo "ERROR: Unable to register the system"
            return 1
        }
    else
        echo "INFO: System already registered."
    fi
}


if [ -f /etc/redhat-release ]; then
    register_rhsm || exit $?
fi
