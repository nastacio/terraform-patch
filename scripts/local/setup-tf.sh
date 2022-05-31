yum install -y yum-utils \
&& yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo \
&& yum -y install terraform


openshift_install_version=4.10.12
platform=mac
curl -sL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${openshift_install_version}/openshift-install-${platform}.tar.gz | tar xzf - -C /usr/local/bin  && openshift-install version 


mkdir install/temp
cp ./temp/"install-config copy.yaml" ./temp/install-config.yaml

cd install/temp
openshift-install install bootstrap --dir=. \


openshift-install destroy bootstrap --dir=. \
&& openshift-install destroy cluster --dir=.
