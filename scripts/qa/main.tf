# Simplified Terraform for a single EC2 instance using a PEM key (no IPSec Gateway)

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "ipsec_sg" {
  name = "ipsec-lab-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["131.226.32.118/32","209.35.253.0/24","203.169.7.0/24"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["131.226.32.118/32","209.35.253.0/24","203.169.7.0/24"]
  }

  ingress {
    from_port   = 8043
    to_port     = 8043
    protocol    = "tcp"
    cidr_blocks = ["131.226.32.118/32","209.35.253.0/24","203.169.7.0/24"]
  }

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["131.226.32.118/32","209.35.253.0/24","203.169.7.0/24"]
  }

  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["131.226.32.118/32","209.35.253.0/24","203.169.7.0/24"]
  }

  ingress {
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["131.226.32.118/32","209.35.253.0/24","203.169.7.0/24"]
  }

  ingress {
    from_port   = 51821
    to_port     = 51821
    protocol    = "udp"
    cidr_blocks = ["131.226.32.118/32","209.35.253.0/24","203.169.7.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "test_server" {
  ami           = "ami-0fc5d935ebf8bc3bc"
  instance_type = "t3.micro"
  key_name      = "loud_2"
  vpc_security_group_ids = [aws_security_group.ipsec_sg.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
  }

  user_data = file("init-strongswan.sh")

  tags = {
    Name = "qa-test-server"
    Owner = "Louis DeVictoria"
    Department = "Core"
    Temp = "True"
    keep = "10"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt install -y curl strongswan",
      "sudo systemctl enable --now strongswan-starter",
      "sudo apt-get install -y dnsmasq"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/loud_2.pem")
      host        = self.public_ip
    }
  }
}


output "test_server_ip" {
  value = aws_instance.test_server.public_ip
}
