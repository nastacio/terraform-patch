#!/bin/sh

set -x

: "${squid_http_port:=3128}
: "${squid_https_port:=5555}

#
#
#
regiter_rhsm() {
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


#
#
#
function install_squid() {
    # To mount data disk
    # https://docs.microsoft.com/en-us/azure/virtual-machines/linux/add-disk

    # https://access.redhat.com/documentation/en-us/openshift_container_platform/4.10/html-single/installing/index#installing-mirroring-creating-registry

    # https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/deploying_different_types_of_servers/configuring-the-squid-caching-proxy-server_deploying-different-types-of-servers
    # Install Squid

    # To install certbot
    # https://www.cyberithub.com/how-to-install-lets-encrypt-certbot-on-rhel-centos-8/

    dnf update -y \
    && dnf install squid -y \
    && dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y \
    && dnf install certbot python3-certbot-apache -y \
    && dnf install firewalld -y \
    && systemctl start firewalld \
    && firewall-cmd --zone=public --add-port=3128/tcp \
    && firewall-cmd --reload \
    && firewall-cmd --zone=public --add-port=5555/tcp \
    /usr/lib64/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 4MB \
    || result=1

    iptables-save | grep 3128 \

    # https://elatov.github.io/2019/01/using-squid-to-proxy-ssl-sites/
    # certbot certonly --standalone --preferred-challenges http --http-01-port 80 --deploy-hook 'systemctl reload squid' -d "bastion.${BASE_DOMAIN}" --test-cert

    # Reverse proxy
    # https://access.redhat.com/solutions/36303
    # https://help.univention.com/t/cool-solution-squid-as-reverse-ssl-proxy/14714

#     https_port 5555 vhost \
#    cert=/etc/letsencrypt/live/bastion.cp-shared.stackpoc.cloudpak-bringup.com-0001/fullchain.pem \
#    key=/etc/letsencrypt/live/bastion.cp-shared.stackpoc.cloudpak-bringup.com-0001/privkey.pem
# cache_peer 38.102.181.34 parent 8443 0 no-query originserver ssl sslflags=DONT_VERIFY_PEER name=myHost
}


#
#
#
function configure_squid() {

}

if [ -f /etc/redhat-release ]; then
    regiter_rhsm || exit $?
fi

install_squid || exit $?
