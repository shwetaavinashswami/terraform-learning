#Credentials
provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "${var.region}"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "shweta-tf-test"
  acl    = "private"

  tags {
    Name        = "Demo"
    Environment = "Demo"
  }
}

#VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "192.168.0.0/16"
}

#Internet gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = "${aws_vpc.my_vpc.id}"
}

#Route Table
resource "aws_route" "internet_access" {
  route_table_id = "${aws_vpc.my_vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = "${aws_internet_gateway.my_igw.id}"
}

#Subnet
resource "aws_subnet" "my_subnet" {
  vpc_id = "${aws_vpc.my_vpc.id}"
  cidr_block = "192.168.1.0/24"
  map_public_ip_on_launch = true
}

#Security group
resource "aws_security_group" "ec2_sg" {
  name = "my_vpc_ec2_sg"
  vpc_id = "${aws_vpc.my_vpc.id}"
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_key_pair" "auth" {
  key_name = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

data "aws_availability_zones" "all" {}

## Creating Launch Configuration
resource "aws_launch_configuration" "example" {
  image_id               = "${lookup(var.amis,var.region)}"
  instance_type          = "t2.micro"
  security_groups        = ["${aws_security_group.ec2_sg.id}"]
  key_name               = "${var.key_name}"
  iam_instance_profile  = "${aws_iam_instance_profile.s3_instance_profile.id}"
  user_data = <<-EOF
              #!/bin/bash
                echo $(curl http://169.254.169.254/latest/meta-data/ami-id) > metadata.txt
                echo ' '
                echo $(curl http://169.254.169.254/latest/meta-data/hostname) >> metadata.txt
                echo ' '
                aws s3 cp metadata.txt s3://shweta-tf-test/ --region ap-south-1

              EOF
  lifecycle {
    create_before_destroy = true
  }
}
## Creating AutoScaling Group
resource "aws_autoscaling_group" "example" {
  launch_configuration = "${aws_launch_configuration.example.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]
   vpc_zone_identifier = ["${aws_subnet.my_subnet.id}"]
  min_size = 1
  max_size = 3
  health_check_type = "EC2"

}

resource "aws_iam_role" "s3_role" {
  name = "s3_role_role"
  assume_role_policy = <<EOF
{
"Version": "2012-10-17",
"Statement": [
  {
    "Effect": "Allow",
    "Principal": {
      "Service": "ec2.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }
]
}
EOF
}

resource "aws_iam_role_policy" "s3_policy" {
  name = "s3_instance_role"
  role = "${aws_iam_role.s3_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "s3_instance_profile" {
  name = "s3_instance_profile"
  roles = ["${aws_iam_role.s3_role.name}"]
}




#Variables

variable "access_key" {}

variable "secret_key" {}

variable "region" {
  default = "ap-south-1"
}

variable "key_name" {
  description = "Name of your AWS keypair"
  default = "my_key"
}

variable "public_key_path" {
  description = "Path to your public key"
  default = "/root/.ssh/id_rsa.pub"
}

variable "private_key_path" {
  description = "Path to your private key"
  default = "/root/.ssh/id_rsa"
}

variable "amis" {
  type = "map"
  default = {
    ap-south-1 = "ami-7c87d913"

  }
}
