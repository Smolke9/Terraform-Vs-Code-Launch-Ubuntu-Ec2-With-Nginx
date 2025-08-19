terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
  }
}

# -------- Variables --------
variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "profile" {
  description = "AWS CLI profile name to use"
  type        = string
  default     = "dev"   # change if you used a different profile
}

variable "key_name" {
  description = "Name of the EC2 Key Pair"
  type        = string
  default     = "ubuntuu11"
}

# -------- Provider --------
provider "aws" {
  region  = var.region
  profile = var.profile
}

# -------- Get latest Ubuntu 22.04 LTS AMI (Canonical) --------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -------- Security Group (SSH 22, HTTP 80) --------
resource "aws_security_group" "web_sg" {
  name        = "tf-web-sg"
  description = "Allow SSH and HTTP"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  tags = {
    Name = "tf-web-sg"
  }
}

# -------- Generate SSH key and create AWS Key Pair --------
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "kp" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Save private key to local file (secure permissions on Linux/macOS)
resource "local_file" "pem" {
  filename        = "${var.key_name}.pem"
  content         = tls_private_key.ssh_key.private_key_pem
  file_permission = "0400"
}

# -------- EC2 Instance with Nginx preinstalled --------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.kp.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name = "tf-nginx-ubuntu"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -eux
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -y
              apt-get install -y nginx
              systemctl enable nginx

              # Clean default page(s)
              rm -f /var/www/html/index.nginx-debian.html /var/www/html/index.html || true

              # Create custom HTML
              cat > /var/www/html/index.html <<'HTML'
              <!DOCTYPE html>
              <html lang="en">
              <head>
                <meta charset="UTF-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1.0" />
                <title>Welcome to My Terraform Nginx Server</title>
                <style>
                  body { background:#f4f4f4; font-family: Arial, sans-serif; text-align:center; padding-top:50px; }
                  h1 { color:#2c3e50; }
                  p { color:#555; }
                  .box { background:#fff; padding:20px; border-radius:10px; box-shadow:0 4px 6px rgba(0,0,0,.1); display:inline-block; }
                </style>
              </head>
              <body>
                <div class="box">
                  <h1>Hello from Terraform + Nginx 🚀</h1>
                  <p>This page was deployed automatically using <b>user_data</b>!</p>
                </div>
              </body>
              </html>
              HTML

              systemctl restart nginx
              EOF

  # Optionally save important values to files on your machine
  provisioner "local-exec" {
    command = "echo ${self.public_ip} > ip.txt"
  }
  provisioner "local-exec" {
    command = "echo ${self.private_ip} > pvtip.txt"
  }
  provisioner "local-exec" {
    command = "echo ${self.id} > id.txt"
  }
}

# -------- Outputs --------
output "public_ip" {
  value = aws_instance.web.public_ip
}

output "public_dns" {
  value = aws_instance.web.public_dns
}

output "ssh_command" {
  value = "ssh -i ./${var.key_name}.pem ubuntu@${aws_instance.web.public_ip}"
}
