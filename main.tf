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

variable "registry_username" {
  description = "Mirrored registry username."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "registry_password" {
  description = "Mirrored registry password."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "rhsm_username" {
  description = "Red Hat subscription username."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "rhel_pull_secret" {
  description = "Red Hat Image Pull secret."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "rhsm_password" {
  description = "Red Hat subscription password."
  nullable    = false
  sensitive   = true
  type        = string
}
variable "bastion_hostname" {
  description = "Hostname for the bastion server."
  nullable    = false
  type        = string
}
variable "ssh_public_key" {
  description = "File name containing public SSH key added to all instances created with this plan."
  nullable    = false
  type        = string
}
variable "ssh_private_key" {
  description = "File name containing private SSH key used for remote execution on instances."
  nullable    = false
  type        = string
}
variable "route_53_zone_id" {
  description = "Zone identifier for the Route 53 instance."
  nullable    = false
  type        = string
}


#
# Configure the AWS Provider
#
provider "aws" {
  profile = "default"
  region  = "us-east-1"

  default_tags {
    tags = {
      Environment = "sdlc1"
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
resource "aws_vpc" "sdlc1_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "sdlc1-vpc"
  }
}

resource "aws_internet_gateway" "sdlc1_vpc_gw" {
  vpc_id = aws_vpc.sdlc1_vpc.id

  tags = {
    Name = "sdlc1-eip"
  }
}

resource "aws_subnet" "sdlc1_subnet" {
  availability_zone       = "us-east-1a"
  cidr_block              = cidrsubnet(aws_vpc.sdlc1_vpc.cidr_block, 3, 1)
  map_public_ip_on_launch = true
  tags = {
    Name = "sdlc1-subnet"
  }
  vpc_id = aws_vpc.sdlc1_vpc.id

  depends_on = [aws_internet_gateway.sdlc1_vpc_gw]
}

# resource "aws_network_interface" "sdlc1-sni" {
#   subnet_id   = aws_subnet.sdlc1_subnet.id

#   tags = {
#     Name = "primary_network_interface"
#   }
# }

resource "aws_security_group" "sdlc1_ssh_sg" {
  name   = "allow-ssh-sg"
  vpc_id = aws_vpc.sdlc1_vpc.id
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
    Name = "sdlc1-ssh-sg"
  }
}
resource "aws_security_group" "sdlc1_web_sg" {
  name   = "allow-all-sg"
  vpc_id = aws_vpc.sdlc1_vpc.id
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
    Name = "sdlc1-web-sg"
  }
}
resource "aws_security_group" "sdlc1_squid_sg" {
  name   = "allow-squid-sg"
  vpc_id = aws_vpc.sdlc1_vpc.id
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
    Name = "sdlc1-squid-sg"
  }
}
resource "aws_security_group" "sdlc1_squid_tls_sg" {
  name   = "allow-squid-tls-sg"
  vpc_id = aws_vpc.sdlc1_vpc.id
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
    Name = "sdlc1-squid-tls-sg"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("${var.ssh_public_key}")

  tags = {
    Name = "sdlc1-ssh-key"
  }
}

#
#
#
resource "aws_route53_record" "bastion-dns" {
  zone_id = data.aws_route53_zone.dns_zone.zone_id
  name    = var.bastion_hostname
  type    = "A"
  ttl     = "300"
  records = [aws_eip.sdlc1_lb.public_ip]
}

# Create bastion instance in the VPC
resource "aws_instance" "sdlc1_bastion_instance" {
  ami               = "ami-0b0af3577fe5e3532"
  availability_zone = "us-east-1a"

  # Establishes connection to be used by all
  # generic remote provisioners (i.e. file/remote-exec)
  # https://www.terraform.io/language/resources/provisioners/connection
  connection {
    private_key = file("${var.ssh_private_key}")
    host        = self.public_ip
    type        = "ssh"
    user        = "ec2-user"
  }

  key_name      = aws_key_pair.deployer.key_name
  instance_type = "c6a.large"

  provisioner "file" {
    source      = "scripts/install-squid.sh"
    destination = "/tmp/install-squid.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-squid.sh",
      "/tmp/install-squid.sh ${var.bastion_hostname} ${var.registry_username} ${var.registry_password} ${var.rhsm_username} ${var.rhsm_password} '${var.rhel_pull_secret}' > /tmp/log1.txt 2>&1",
    ]
  }

  subnet_id = aws_subnet.sdlc1_subnet.id
  vpc_security_group_ids = [
    aws_security_group.sdlc1_ssh_sg.id,
    aws_security_group.sdlc1_web_sg.id,
    aws_security_group.sdlc1_squid_sg.id,
    aws_security_group.sdlc1_squid_tls_sg.id
  ]

  tags = {
    Name = "sdlc1-bastion"
  }
}

#
#
#
resource "aws_eip" "sdlc1_lb" {
  instance = aws_instance.sdlc1_bastion_instance.id
  vpc      = true

  tags = {
    Name = "sdlc1-eip"
  }
}

#
#
#
resource "aws_route_table" "sdlc1_vpc_route_table" {
  vpc_id = aws_vpc.sdlc1_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sdlc1_vpc_gw.id
  }
  tags = {
    Name = "sdlc1-vpc-route-table"
  }
}

#
#
#
resource "aws_route_table_association" "subnet_association" {
  subnet_id      = aws_subnet.sdlc1_subnet.id
  route_table_id = aws_route_table.sdlc1_vpc_route_table.id
}
