#!/bin/sh

set -x

: "${bastion_hostname:=${1}}"
: "${quay_ip:=${2}}"
: "${cert_owner:=${3}}"

: "${squid_http_port:=3128}
: "${squid_https_port:=5555}


#
#
#
function install_squid() {

    echo "INFO: Starting Squid Installation"
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
    || result=1

    # Reverse proxy
    # https://access.redhat.com/solutions/36303
    # https://help.univention.com/t/cool-solution-squid-as-reverse-ssl-proxy/14714
}


#
#
#
function configure_squid() {
    firewall-cmd --zone=public --add-port=${squid_http_port}/tcp \
    && firewall-cmd --reload \
    && firewall-cmd --zone=public --add-port=${squid_https_port}/tcp \
    && if [ ! -e /var/spool/squid/ssl_db ]; then
            /usr/lib64/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 4MB
    fi \
    && certbot certonly \
        --standalone \
        --preferred-challenges http -\
        -http-01-port 80 \
        --deploy-hook 'systemctl reload squid' \
        -d "${bastion_hostname}" \
        --test-cert \
        -m "${cert_owner}" \
        --agree-tos \
        -n \
    && sed -i "s/%%SQUID_FQDN%%/${bastion_hostname}/" /tmp/squid.conf \
    && sed -i "s/%%REGISTRY_IP%%/${quay_ip}/" /tmp/squid.conf \
    && mv /tmp/squid.conf /etc/squid/squid.conf \
    || result=1
}

install_squid \
&& configure_squid \
|| exit $?
