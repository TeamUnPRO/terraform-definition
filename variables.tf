variable "public_key_path" {
  default = "~/.ssh/teamunpro-pw.pub"
}

variable "key_name" {
  description = "Desired name of AWS key pair"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default = "us-east-1"
}

variable "aws_ecs_amis" {
  default = {
    us-east-1 = "ami-a1fa1acc"
  }
}

variable "aws_nat_amis" {
  default = {
    us-east-1 = "ami-f5f41398"
  }
}

variable "aws_ubuntu_amis" {
  default = {
    us-east-1 = "ami-840910ee"
  }
}

variable "vpn_cidr_block" {
  default = "172.20.254.0/24"
}

variable "mumble_public_ip" {
}
