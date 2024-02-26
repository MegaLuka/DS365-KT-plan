terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "instance_parameters" {
  source = "./child_module"
}


# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# NETWORK COMPONENTS
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "my_internet_gateway" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "my_subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
   availability_zone = "us-east-1a"
}

resource "aws_security_group" "my_security_group" {
  name        = "my_security_group"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "my_security_group"
  }
}

resource "aws_vpc_security_group_ingress_rule" "my_security_group_ipv4" {
  security_group_id = aws_security_group.my_security_group.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "allow_3389" {
  security_group_id = aws_security_group.my_security_group.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 3389
  ip_protocol       = "tcp"
  to_port           = 3389
}

resource "aws_vpc_security_group_ingress_rule" "allow_22" {
  security_group_id = aws_security_group.my_security_group.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.my_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_network_interface" "my_network_interface" {
  subnet_id   = aws_subnet.my_subnet.id
  private_ips = ["10.0.1.10"]
  security_groups = [aws_security_group.my_security_group.id]
}

# EC2
data "aws_ami" "amazon-window-2023-ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-2024.01.16"]
  }
}


resource "aws_instance" "my_instance" {
  ami               = data.aws_ami.amazon-window-2023-ami.id
  availability_zone = "us-east-1a"
  instance_type     = "t3.micro"
  key_name          = module.instance_parameters.instance_key #module usage
  #subnet_id         = aws_subnet.my_subnet.id  => network interface already in the subnet - caused error network_interface

  network_interface {
    network_interface_id = aws_network_interface.my_network_interface.id
    device_index         = 0
  }

  lifecycle { # add this block for life cycle -> affect plan and apply
    create_before_destroy = true #create a new resource before destroy
    #prevent_destroy = true  #prevent destroy this resource

  }
}

# Create ebs volume
resource "aws_ebs_volume" "ebs" {
  availability_zone = "us-east-1a"
  size              = 8
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs.id
  instance_id = aws_instance.my_instance.id
}

resource "aws_eip" "my_eip" {
  domain = "vpc"
  instance                  = aws_instance.my_instance.id
  associate_with_private_ip = "10.0.1.10"
  depends_on                = [aws_internet_gateway.my_internet_gateway]
}


resource "aws_cloudwatch_metric_alarm" "alarm" {
  alarm_name                = "ec2-cpu-alarm"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = 2
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 120
  statistic                 = "Average"
  threshold                 = 40
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
}

