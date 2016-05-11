provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

#
# Network
#
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

resource "aws_subnet" "public" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
}

resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "private"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

resource "aws_route" "private_internet_access" {
  route_table_id         = "${aws_route_table.private.id}"
  destination_cidr_block = "0.0.0.0/0"
  instance_id ="${aws_instance.nat.id}"
}

resource "aws_route" "vpn_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "${var.vpn_cidr_block}"
  instance_id ="${aws_instance.vpn.id}"
}

#
# ECS
#
resource "aws_ecs_cluster" "default" {
  name = "default"
}

#
# DNS
#
resource "aws_route53_zone" "teamunpro" {
  name = "teamunpro.com"
}

resource "aws_route53_zone" "local" {
  name = "aws.teamunpro"
}

resource "aws_route53_record" "mumble" {
  zone_id = "${aws_route53_zone.teamunpro.zone_id}"
  name = "mumble.teamunpro.com"
  type = "A"
  ttl = "300"
  records = ["${var.mumble_public_ip}"]
}

resource "aws_route53_record" "vpn" {
  zone_id = "${aws_route53_zone.teamunpro.zone_id}"
  name = "vpn.teamunpro.com"
  type = "A"
  ttl = "300"
  records = ["${aws_instance.vpn.public_ip}"]
}

#
# Security Groups
#
resource "aws_security_group" "default" {
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "-1"
    cidr_blocks = ["${aws_subnet.public.cidr_block}", "${var.vpn_cidr_block}"]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mumble" {
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 64738
    to_port     = 64738
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 64738
    to_port     = 64738
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vpn" {
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ssh" {
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#
# IAM
#
resource "aws_iam_role_policy" "salt_pillar" {
  name = "UnproSaltPillarPolicy"
  role = "${aws_iam_role.salt_master.id}"
  policy=  <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::pillar-teamunpro",
        "arn:aws:s3:::pillar-teamunpro/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_data" {
  name = "UnproECSDataPolicy"
  role = "${aws_iam_role.ecs.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::ecs-data-teamunpro",
        "arn:aws:s3:::ecs-data-teamunpro/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "associate_address" {
  name = "UnproAssociateAddressPolicy"
  role = "${aws_iam_role.ecs.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:AssociateAddress",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ec2_tags" {
  name = "UnproAssociateAddressPolicy"
  role = "${aws_iam_role.default.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:AssociateAddress",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "ecs" {
  name = "ECSRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role" "salt_master" {
  name = "SaltMasterRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role" "default" {
  name = "DefaultRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ecs" {
    name = "ECSInstanceProfile"
    roles = ["${aws_iam_role.ecs.name}"]
}

resource "aws_iam_instance_profile" "salt_master" {
    name = "SaltMasterInstanceProfile"
    roles = ["${aws_iam_role.salt_master.name}"]
}

resource "aws_iam_instance_profile" "default" {
    name = "SaltMasterInstanceProfile"
    roles = ["${aws_iam_role.default.name}"]
}

#
# Instances
#
resource "aws_instance" "ecs" {
  count = 1
  tags {
    Name = "ecs-${count.index}"
    Roles = "docker"
    Network = "public"
  }

  connection {
    user = "ec2-user"
  }

  instance_type = "m2.micro"

  ami = "${lookup(var.aws_ecs_amis, var.aws_region)}"

  key_name = "${aws_key_pair.auth.id}"

  iam_instance_profile = "${aws_iam_instance_profile.ecs.id}"

  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  subnet_id = "${aws_subnet.public.id}"

  provisioner "remote-exec" {
    inline = [
      "echo ECS_CLUSTER=${aws_ecs_cluster.default.name} >> /etc/ecs/ecs.config"
    ]
  }
}

resource "aws_instance" "nat" {
  tags {
    Name = "nat"
    Roles = "nat"
    Network = "public"
  }

  connection {
    user = "ec2-user"
  }

  instance_type = "m2.nano"

  ami = "${lookup(var.aws_nat_amis, var.aws_region)}"

  key_name = "${aws_key_pair.auth.id}"

  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  subnet_id = "${aws_subnet.public.id}"

  user_data = "${file("salt-minion.sh")}"
}

resource "aws_instance" "salt-master" {
  tags {
    Name = "salt-master"
    Roles = "salt-master"
    Network = "private"
  }

  connection {
    user = "ubuntu"
  }

  instance_type = "m2.nano"

  ami = "${lookup(var.aws_ubuntu_amis, var.aws_region)}"

  iam_instance_profile = "${aws_iam_instance_profile.salt_master.id}"

  key_name = "${aws_key_pair.auth.id}"

  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  subnet_id = "${aws_subnet.private.id}"

  user_data = "${file("salt-master.sh")}"
}

resource "aws_instance" "vpn" {
  tags {
    Name = "vpn"
    Roles = "vpn"
    Network = "public"
  }

  connection {
    user = "ubuntu"
  }

  instance_type = "m2.nano"

  ami = "${lookup(var.aws_ubuntu_amis, var.aws_region)}"

  key_name = "${aws_key_pair.auth.id}"

  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  source_dest_check = "false"

  subnet_id = "${aws_subnet.public.id}"

  user_data = "${file("salt-minion.sh")}"
}
