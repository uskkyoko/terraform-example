# ---------------------------------------------------------------------------
# 1. Look things up (data sources): nothing is created here
# ---------------------------------------------------------------------------

# Every new AWS account comes with a "default VPC" in each region.
# Using it keeps this example short: no subnets, route tables or gateways to write.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Ubuntu 24.04 LTS image published by Canonical.
# Architecture must match the instance type (t2/t3 = x86_64, t4g = arm64).
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-*-server-*"]
  }

  filter {
    name   = "architecture"
    values = [var.instance_type == "t4g.micro" ? "arm64" : "x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# 2. Create resources
# ---------------------------------------------------------------------------

# Upload your public key so AWS can place it on the VM at boot.
resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# A security group is a firewall attached to the VM.
resource "aws_security_group" "vm" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH and HTTP to the demo VM"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic (apt-get needs this)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The virtual machine itself.
resource "aws_instance" "vm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.vm.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  # Free tier includes up to 30 GB of gp3 storage. 8 GB is plenty here.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  # Runs once on first boot as root: installs a web server and a hello page.
  user_data = <<-CLOUDINIT
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y nginx
    cat > /var/www/html/index.html <<HTML
    <h1>Hello from Terraform!</h1>
    <p>Instance: $(hostname)</p>
    <p>New change</p>
    HTML
    systemctl enable --now nginx
  CLOUDINIT

  # Security hardening that costs nothing: require IMDSv2.
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-vm"
    Owner = "Uliana"
  }
}
