#!/bin/sh

set -x

: "${bastion_hostname:=${1}}"
: "${quay_ip:=${2}}"
: "${cert_owner:=${3}}"

: "${squid_http_port:=3128}
: "${squid_https_port:=5555}


#
# Installs and starts Squid and dependencies if not already installed.
#
# https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/deploying_different_types_of_servers/configuring-the-squid-caching-proxy-server_deploying-different-types-of-servers
#
function install_squid() {

    echo "INFO: Starting Squid Installation"
    
    # To install certbot
    # https://www.cyberithub.com/how-to-install-lets-encrypt-certbot-on-rhel-centos-8/

    echo "INFO: Updating repos" \
    && dnf update -y \
    && echo "INFO: Installing Squid" \
    && dnf install squid -y \
    && echo "INFO: Installing Certbot" \
    && dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y \
    && dnf install certbot python3-certbot-apache -y \
    && echo "INFO: Starting squid" \
    && systemctl start squid \
    && dnf install firewalld -y \
    && echo "INFO: Starting firewall" \
    && systemctl start firewalld \
    && echo "INFO: Squid installation complete." \
    || result=1

    # Reverse proxy
    # https://access.redhat.com/solutions/36303
    # https://help.univention.com/t/cool-solution-squid-as-reverse-ssl-proxy/14714
}


#
#
#
function configure_squid() {
    echo "INFO: Open inbound ports in local firewall." \
    firewall-cmd --zone=public --add-port=${squid_http_port}/tcp --permenant \
    && firewall-cmd --zone=public --add-port=${squid_https_port}/tcp --permanent \
    && if [ ! -e /var/spool/squid/ssl_db ]; then
            /usr/lib64/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 4MB
    fi \
    && echo "INFO Acquire cert for proxy" \
    && firewall-cmd --zone=public --add-port=80/tcp \
    && certbot certonly \
        --standalone \
        --preferred-challenges http \
        --http-01-port 80 \
        -d "${bastion_hostname}" \
        -m "${cert_owner}" \
        --agree-tos \
        -n \
    && firewall-cmd --reload \
    && echo "INFO: Reconfigure squid to use new certs." \
    && tmp_squid_conf=/tmp/squid.conf \
    && sed -i "s/%%SQUID_FQDN%%/${bastion_hostname}/" "${tmp_squid_conf}" \
    && sed -i "s/%%REGISTRY_IP%%/${quay_ip}/" "${tmp_squid_conf}" \
    && rm -rf /etc/squid/squid.conf.old \
    && mv /etc/squid/squid.conf /etc/squid/squid.conf.old \
    && cp "${tmp_squid_conf}" /etc/squid/squid.conf \
    && systemctl restart squid \
    && systemctl status squid \
    && echo "INFO: Squid restart complete." \
    || result=1

    echo "INFO: Closing temporary ports, like http/80." \
    && firewall-cmd --reload \
    && echo "INFO: Squid configuration complete." \
    || {
        echo "WARNING: Closing HTTP port failed." \
        result=1
    }

    return ${result}
}

install_squid \
&& configure_squid \
|| exit $?
