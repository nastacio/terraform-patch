#
# Thanks to Terraform docs and to Hasitha Algewatta for his excellent
# article: https://medium.com/@hmalgewatta/setting-up-an-aws-ec2-instance-with-ssh-access-using-terraform-c336c812322f
#

#
#
#
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
  required_version = ">= 0.14.9"
}




#
# Configure the AWS Provider
#
provider "aws" {
  profile = "default"
  region  = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment_name
      Service     = "Example"
    }
  }
}

#
# Reference to the pre-existing DNS zone
#
data "aws_route53_zone" "dns_zone" {
  zone_id = var.route_53_zone_id
}

# Create a VPC
resource "aws_vpc" "lab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${var.environment_name}-vpc"
  }
}

resource "aws_internet_gateway" "vpc_gw" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = {
    Name = "${var.environment_name}-eip"
  }
}

resource "aws_subnet" "lab_subnet" {
  availability_zone       = "${var.aws_region}a"
  cidr_block              = cidrsubnet(aws_vpc.lab_vpc.cidr_block, 3, 1)
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.environment_name}-subnet"
  }
  vpc_id = aws_vpc.lab_vpc.id

  depends_on = [aws_internet_gateway.vpc_gw]
}

resource "aws_subnet" "lab_subnet_private" {
  availability_zone       = "${var.aws_region}a"
  cidr_block              = cidrsubnet(aws_vpc.lab_vpc.cidr_block, 3, 7)
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.environment_name}-subnet"
  }
  vpc_id = aws_vpc.lab_vpc.id

  depends_on = [aws_internet_gateway.vpc_gw]
}

# resource "aws_network_interface" "sdlc1-sni" {
#   subnet_id   = aws_subnet.lab_subnet.id

#   tags = {
#     Name = "primary_network_interface"
#   }
# }

resource "aws_security_group" "lab_ssh_sg" {
  name   = "allow-ssh-sg"
  vpc_id = aws_vpc.lab_vpc.id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }
  // Terraform removes the default rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment_name}-ssh-sg"
  }
}
resource "aws_security_group" "lab_web_sg" {
  name   = "allow-all-sg"
  vpc_id = aws_vpc.lab_vpc.id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
  }
  // Terraform removes the default rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment_name}-web-sg"
  }
}
resource "aws_security_group" "lab_squid_sg" {
  name   = "allow-squid-sg"
  vpc_id = aws_vpc.lab_vpc.id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 3128
    to_port   = 3128
    protocol  = "tcp"
  }
  // Terraform removes the default rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment_name}-squid-sg"
  }
}
resource "aws_security_group" "lab_squid_tls_sg" {
  name   = "allow-squid-tls-sg"
  vpc_id = aws_vpc.lab_vpc.id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 5555
    to_port   = 5555
    protocol  = "tcp"
  }
  // Terraform removes the default rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment_name}-squid-tls-sg"
  }
}

resource "aws_security_group" "lab_registry_tls_sg" {
  name   = "allow-registry-tls-sg"
  vpc_id = aws_vpc.lab_vpc.id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 8443
    to_port   = 8443
    protocol  = "tcp"
  }
  // Terraform removes the default rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment_name}-registry-tls-sg"
  }
}


resource "aws_key_pair" "deployer" {
  # key_name   = "deployer-key"
  public_key = file("${var.ssh_public_key}")

  tags = {
    Name = "${var.environment_name}-ssh-key"
  }
}

#
#
#
resource "aws_route53_record" "bastion-dns" {
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.dns_zone.zone_id
  name            = var.bastion_hostname
  type            = "A"
  ttl             = "300"
  records         = [aws_eip.lab_lb.public_ip]
}


#
# Create registry instance in the VPC
#
resource "aws_network_interface" "lab_registry_nic" {
  subnet_id  = aws_subnet.lab_subnet.id
  # private_ip = cidrhost(aws_subnet.lab_subnet.cidr_block, 1)
  security_groups = [
    aws_security_group.lab_ssh_sg.id,
    aws_security_group.lab_squid_tls_sg.id
  ]
  attachment {
    instance     = aws_instance.registry_instance.id
    device_index = 1
  }
  tags = {
    Name = "${var.environment_name}-registry-nic"
  }
}


resource "aws_instance" "registry_instance" {
  # RHEL 8.4
  ami = "ami-0b0af3577fe5e3532"
  
  associate_public_ip_address = true
  availability_zone           = "${var.aws_region}a"
  key_name                    = aws_key_pair.deployer.key_name
  instance_type               = "c6a.large"

  root_block_device {
    delete_on_termination = true
    tags = {
      Name = "${var.environment_name}-registry-block"
    }
    volume_size = 256
    volume_type = "gp2"
  }
  subnet_id = aws_subnet.lab_subnet.id
  vpc_security_group_ids = [
    aws_security_group.lab_ssh_sg.id,
    aws_security_group.lab_registry_tls_sg.id
  ]

  tags = {
    Name = "${var.environment_name}-registry"
  }
}

# Create bastion instance in the VPC
resource "aws_instance" "bastion_instance" {
  # RHEL 8.4
  ami = "ami-0b0af3577fe5e3532"

  associate_public_ip_address = true
  availability_zone           = "${var.aws_region}a"
  key_name                    = aws_key_pair.deployer.key_name
  instance_type               = "c6a.large"

  subnet_id                   = aws_subnet.lab_subnet.id
  vpc_security_group_ids      = [
    aws_security_group.lab_ssh_sg.id,
    aws_security_group.lab_web_sg.id,
    aws_security_group.lab_squid_sg.id,
    aws_security_group.lab_squid_tls_sg.id
  ]

  tags = {
    Name = "${var.environment_name}-bastion"
  }
}

#
#
#
resource "aws_eip" "lab_lb" {
  instance = aws_instance.bastion_instance.id
  vpc      = true

  tags = {
    Name = "${var.environment_name}-eip"
  }
}

#
#
#
resource "aws_route_table" "lab_vpc_route_table" {
  vpc_id = aws_vpc.lab_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpc_gw.id
  }
  tags = {
    Name = "${var.environment_name}-vpc-route-table"
  }
}

#
#
#
resource "aws_route_table_association" "subnet_association" {
  subnet_id      = aws_subnet.lab_subnet.id
  route_table_id = aws_route_table.lab_vpc_route_table.id
}

resource "aws_eip" "natgw_a_eip" {
  vpc = true
}

resource "aws_nat_gateway" "natgw_a" {
  allocation_id = aws_eip.natgw_a_eip.id
  subnet_id     = aws_subnet.lab_subnet.id

  tags = {
    Name = "${var.environment_name}-nat-zone-a"
  }
}


resource "aws_route_table" "lab_vpc_route_table_private" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_nat_gateway.natgw_a.id
  }

  tags = {
    Name = "${var.environment_name}-vpc-route-table-private"
  }
}

resource "aws_route_table_association" "subnet_association_private" {
    subnet_id      = aws_subnet.lab_subnet_private.id
    route_table_id = aws_route_table.lab_vpc_route_table_private.id
}

/*
  Update NAT instance with OCP rules
*/
resource "aws_security_group" "vpc-nat" {
    name = "${var.environment_name}-vpc-ocp-nat"
    description = "Allow traffic to pass from the private subnet to the internet and allow incoming"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [var.ocp_private_subnet_cidr_a]

    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [var.ocp_private_subnet_cidr_a]
    }
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 1024
        to_port = 65535
        protocol = "tcp"
        cidr_blocks = [var.ocp_private_subnet_cidr_a]
    }

    egress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        cidr_blocks = [var.ocp_private_subnet_cidr_a]
    }

    vpc_id = aws_vpc.lab_vpc.id

    tags = {
        Name = "OCPNATSG"
    }
}

resource "null_resource" "configure_registry" {
  # https://www.terraform.io/language/resources/provisioners/connection
  connection {
    bastion_host        = aws_eip.lab_lb.public_ip
    bastion_host_key    = file("${var.ssh_public_key}")
    bastion_port        = 22
    bastion_user        = "ec2-user"
    bastion_private_key = file("${var.ssh_private_key}")
    host                = aws_instance.registry_instance.private_ip
    private_key         = file("${var.ssh_private_key}")
    type                = "ssh"
    user                = "ec2-user"
  }

  provisioner "file" {
    source      = "scripts/clone-ocp-images.sh"
    destination = "/tmp/clone-ocp-images.sh"
  }

  provisioner "file" {
    source      = "scripts/install-quay.sh"
    destination = "/tmp/install-quay.sh"
  }

  provisioner "file" {
    source      = "scripts/register-rhel.sh"
    destination = "/tmp/register-rhel.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/register-rhel.sh",
      "sudo /tmp/register-rhel.sh aws-${var.environment_name}-registry ${var.rhsm_username} ${var.rhsm_password} | grep -v username | grep -v password > /tmp/register-rhel.txt 2>&1",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-quay.sh",
      "sudo /tmp/install-quay.sh ${var.quay_hostname} ${var.registry_username} ${var.registry_password} | grep -v ${var.registry_password} > /tmp/install-quay.txt 2>&1",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/clone-ocp-images.sh",
      "sudo /tmp/clone-ocp-images.sh ${var.quay_hostname} ${var.registry_username} ${var.registry_password} ${var.rhel_pull_secret} | grep -v username | grep -v password > /tmp/clone-ocp-images.txt 2>&1",
    ]
  }
}

# https://www.devopsschool.com/blog/how-to-run-provisioners-code-after-resources-is-created-in-terraform/
resource "null_resource" "configure_squid" {

  connection {
    private_key = file("${var.ssh_private_key}")
    host        = aws_eip.lab_lb.public_ip
    type        = "ssh"
    user        = "ec2-user"
  }

  provisioner "file" {
    source      = "conf/squid.conf"
    destination = "/tmp/squid.conf"
  }

  provisioner "file" {
    source      = "scripts/register-rhel.sh"
    destination = "/tmp/register-rhel.sh"
  }

  provisioner "file" {
    source      = "scripts/install-squid.sh"
    destination = "/tmp/install-squid.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/register-rhel.sh",
      "sudo /tmp/register-rhel.sh aws-${var.environment_name}-bastion ${var.rhsm_username} ${var.rhsm_password} | grep -v username | grep -v password > /tmp/register-rhel.txt 2>&1",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-squid.sh",
      "sudo /tmp/install-squid.sh ${var.bastion_hostname} ${aws_instance.registry_instance.private_ip} ${var.cert_owner} | grep -v username | grep -v password > /tmp/install-squid.txt 2>&1",
    ]
  }
}

output "vpc_id" {
  value     = aws_vpc.lab_vpc.id
  sensitive = true
}

output "aws_internet_gateway_id" {
  value     = aws_internet_gateway.vpc_gw.id
  sensitive = true
}
