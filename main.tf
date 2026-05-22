terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "my-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
}

# Subnet
resource "aws_subnet" "my_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "my-subnet"
  }
}

# Route Table
resource "aws_route_table" "my_rot" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "my-route-table"
  }
}

# Route Table Association
resource "aws_route_table_association" "attach_subnet" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_rot.id
}

# Security Group
resource "aws_security_group" "web_sg" {
  name_prefix = "terraform-sg-"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-security-group"
  }
}

# EC2 Instance
resource "aws_instance" "web" {

  ami           = "ami-0f58b397bc5c1f2e8"
  instance_type = "t3.small"
  key_name      = "awskey"

  subnet_id = aws_subnet.my_subnet.id

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = true

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("awskey.pem")
    host        = self.public_ip
  }

  provisioner "file" {
    source      = "./deployment.yml"
    destination = "/home/ubuntu/deployment.yml"
  }

  provisioner "file" {
    source      = "./node.service"
    destination = "/home/ubuntu/node.service"
  }

  provisioner "remote-exec" {
    inline = [

      # Update packages
      "sudo apt update -y",

      # Install Docker + Curl + Wget
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io curl wget",

      # Start Docker
      "sudo systemctl enable docker",
      "sudo systemctl start docker",

      # Docker permission
      "sudo chmod 666 /var/run/docker.sock",

      # Install K3s
      "curl -sfL https://get.k3s.io | sh -",

      # Wait for K3s
      "sleep 120",

      # Check K3s
      "sudo systemctl is-active k3s",

      # Create kube config
      "sudo mkdir -p /home/ubuntu/.kube",

      "sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config",

      "sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config",

      # Export KUBECONFIG
      "export KUBECONFIG=/home/ubuntu/.kube/config",

      # Wait until node ready
      "until sudo kubectl get nodes; do sleep 10; done",

      # Check cluster
      "sudo kubectl get nodes",

      "sudo kubectl get pods -A",

      # Deploy application
      "sudo kubectl apply -f /home/ubuntu/deployment.yml",

      # Check services
      "sudo kubectl get svc",

      # INSTALL METRICS SERVER

      "sudo kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml",

      "sleep 60",

      # INSTALL HELM

      "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash",

      # ADD PROMETHEUS REPO

      "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts",

      "helm repo update",

      # INSTALL KUBE STATE METRICS

      "helm install kube-state-metrics prometheus-community/kube-state-metrics -n kube-system",

      "sleep 60",

      # CHECK SERVICE

      "sudo kubectl get svc -n kube-system",

      # EXPOSE SERVICE

      "sudo kubectl patch svc kube-state-metrics -n kube-system -p '{\"spec\":{\"type\":\"NodePort\"}}'",

      # VERIFY

      "sudo kubectl get svc -n kube-system",

      # INSTALL NODE EXPORTER

      "cd /tmp",

      "wget https://github.com/prometheus/node_exporter/releases/download/v1.11.1/node_exporter-1.11.1.linux-amd64.tar.gz",

      "tar -xzf node_exporter-1.11.1.linux-amd64.tar.gz",

      "sudo cp node_exporter-1.11.1.linux-amd64/node_exporter /usr/local/bin/",

      "sudo chmod +x /usr/local/bin/node_exporter",

      # MOVE NODE EXPORTER SERVICE

      "sudo mv /home/ubuntu/node.service /etc/systemd/system/node.service",


      # START NODE EXPORTER

      "sudo systemctl daemon-reload",

      "sudo systemctl enable node.service",

      "sudo systemctl restart node.service",

      "sudo systemctl status node.service --no-pager",

      # FIREWALL PORTS

      "sudo ufw allow 9100/tcp",

      "sudo ufw allow 10250/tcp",

      "sudo ufw allow 30000:32767/tcp",

      "sudo ufw --force enable",

      "sudo ufw reload",

      # FINAL CHECK

      "sudo kubectl get svc -A",

      "sudo kubectl get pods -A"
    ]
  }
  tags = {
    Name = "Terraform-K3s"
  }
}

# Output
output "public_ip" {
  value = aws_instance.web.public_ip
}
