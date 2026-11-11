# ---------------------------------------------------------------------------
# 1. Data sources (read-only lookups)
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

# The default VPC has one public subnet per availability zone (AZ).
# An ALB needs at least two subnets in different AZs, and we spread the
# VMs across them too so one AZ outage does not take everything down.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

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

locals {
  # sort() makes the order stable between runs, so VM 0 always lands in
  # the same subnet and Terraform does not try to move it around.
  subnet_ids = sort(data.aws_subnets.default.ids)
}

# ---------------------------------------------------------------------------
# 2. SSH key
# ---------------------------------------------------------------------------

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# ---------------------------------------------------------------------------
# 3. Security groups: one for the load balancer, one for the VMs
# ---------------------------------------------------------------------------

# The ALB is the only thing the internet talks to on port 80.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP from the internet to the ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "ALB to targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The VMs accept HTTP only from the ALB's security group, not from the world.
# This is the standard pattern: public entry point, private workers.
resource "aws_security_group" "vm" {
  name        = "${var.project_name}-vm-sg"
  description = "Allow HTTP from the ALB and SSH from the student"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from the ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    description = "Allow all outbound (apt-get needs this)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# 4. The VMs (count = var.vm_count)
# ---------------------------------------------------------------------------

resource "aws_instance" "vm" {
  count = var.vm_count

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  # Round-robin the VMs over the available subnets/AZs: 0, 1, 2, 0, 1, ...
  subnet_id                   = local.subnet_ids[count.index % length(local.subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.vm.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  # Each VM serves a page that says which VM it is, so refreshing the ALB URL
  # shows the load balancer rotating between them.
  user_data = <<-CLOUDINIT
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y nginx
    cat > /var/www/html/index.html <<HTML
    <h1>Hello from VM #${count.index}</h1>
    <p>Hostname: $(hostname)</p>
    <p>Private IP: $(hostname -I)</p>
    HTML
    systemctl enable --now nginx
  CLOUDINIT

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-vm-${count.index}"
  }
}

# ---------------------------------------------------------------------------
# 5. Application Load Balancer
# ---------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids
}

# A target group is the list of backends plus the health check that decides
# which of them receive traffic.
resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# One attachment per VM.
resource "aws_lb_target_group_attachment" "web" {
  count = var.vm_count

  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.vm[count.index].id
  port             = 80
}

# The listener: "when a request arrives on port 80, forward it to the target group".
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
