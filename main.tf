terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.75.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "us-east-1"
  access_key = "" # Add your access key
  secret_key = "" # Add your secret key
}

# First, all EC2 related resources
# Create EC2 instance
resource "aws_instance" "main-vpc-instance" {
  ami               = "ami-0f1a6835595fb9246"  # Amazon Linux 2023 AMI
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "main-key"
  subnet_id         = aws_subnet.main-vpc-subnet.id

  vpc_security_group_ids = [aws_security_group.allow_web.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo su
              yum update -y
              yum install -y httpd
              mkdir store-dir
              cd store-dir
              wget https://www.free-css.com/assets/files/free-css-templates/download/page260/e-store.zip
              unzip e-store.zip
              cd ecommerce-html-template
              mv * /var/www/html/
              cd /var/www/html/
              systemctl enable httpd
              systemctl start httpd
              EOF

  # Add this to ensure the instance is ready before being used
  root_block_device {
    delete_on_termination = true
    volume_size           = 8
  }

  tags = {
    Name = "main-vpc-instance"
  }
}

# Create Elastic IP
resource "aws_eip" "one" {
  domain = "vpc"

  instance = aws_instance.main-vpc-instance.id
  depends_on = [
    aws_internet_gateway.gw,
    aws_instance.main-vpc-instance
  ]

  tags = {
    Name = "main-vpc-eip"
  }
}

# Create Security Group
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "allow_web_traffic"
  }
}

# Then networking resources
# Create VPC
resource "aws_vpc" "main-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main-vpc.id

  tags = {
    Name = "main-vpc-igw"
  }
}

# Create Route Table
resource "aws_route_table" "main-vpc-rt" {
  vpc_id = aws_vpc.main-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "main-vpc-rt"
  }
}

# Create Subnet
resource "aws_subnet" "main-vpc-subnet" {
  vpc_id                  = aws_vpc.main-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "main-vpc-subnet"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.main-vpc-subnet.id
  route_table_id = aws_route_table.main-vpc-rt.id
}