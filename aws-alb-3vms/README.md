# Terraform lab 2: three VMs behind an Application Load Balancer

Do lab 1 (`../aws-free-tier-vm`) first. This lab reuses the same ideas and adds
two of the most important ones in cloud infrastructure: **count** (many copies
of one resource) and a **load balancer** in front of them.

Time needed: 60 to 90 minutes. Keep the stack up only while you work on it.

## Quick start

```bash
cd aws-alb-3vms
cp terraform.tfvars.example terraform.tfvars   # aws_region is REQUIRED; set key path if not ~/.ssh/id_ed25519.pub
terraform init
terraform plan                                  # expect: 12 to add
terraform apply                                 # type yes, ~3 minutes
curl $(terraform output -raw alb_url)           # repeat; the VM number changes
terraform destroy                               # type yes, ALWAYS before you leave
```

## What you will build

```
                 internet
                     |
                     v  :80
          +---------------------+       security group "alb": 80 from 0.0.0.0/0
          |  Application LB     |
          |  (2-3 AZs)          |
          +----------+----------+
                     | health check GET /  every 15 s
                     v  :80
          +---------------------+
          |  target group "web" |
          +--+-------+-------+--+
             |       |       |          security group "vm":
             v       v       v            80 only from the "alb" group
          [VM #0] [VM #1] [VM #2]         22 from your IP
           AZ a    AZ b    AZ c          (one t3.micro per AZ, Ubuntu + nginx)
```

Terraform creates 12 resources: 1 key pair, 2 security groups, 3 instances,
1 load balancer, 1 target group, 3 target attachments, 1 listener.

## Cost: this is NOT entirely free. Read before applying.

| Item                      | Legacy free tier (account before 15 Jul 2025)       | Credit-based accounts (after 15 Jul 2025)  |
|---------------------------|-----------------------------------------------------|--------------------------------------------|
| 3 x t3.micro              | 750 instance-hours/month free. 3 VMs use that up in ~10 days | paid from your credits, ~USD 0.03/hour for all three |
| Application Load Balancer | 750 ALB-hours/month + 15 LCU free for 12 months     | paid from credits, ~USD 0.025/hour         |
| Public IPv4 (3 VMs + ALB) | 750 hours free                                      | ~USD 0.03/hour for all                     |

Rough total if you forget it: **about USD 2 per day**. For a 2-hour lab it is
a few cents, or zero on a legacy account. The rule is the same as lab 1:
**`terraform destroy` before you close the laptop**, and have a zero-spend
budget alert configured.

## Prerequisites

Same as lab 1: AWS CLI configured (`aws sts get-caller-identity` works),
Terraform >= 1.5, and an SSH key pair. If you have not done lab 1, read its
section *SSH keys: what they are and what to do with yours* first. In short:
`ls ~/.ssh/*.pub`; if empty run `ssh-keygen -t ed25519`; if you want to use a
key other than `~/.ssh/id_ed25519.pub`, set `ssh_public_key_path` in
`terraform.tfvars`. Your IAM user needs `AmazonEC2FullAccess` and
`ElasticLoadBalancingFullAccess`.

Your region's default VPC must have **at least two subnets** in different AZs.
Every default VPC does.

## Step by step

### 1. Configure

```bash
cd aws-alb-3vms
cp terraform.tfvars.example terraform.tfvars
```

Set `aws_region` to match `aws configure` (`aws configure get region`). It is
**required**; without it Terraform asks `var.aws_region  Enter a value:` on
every command. Optionally set `ssh_allowed_cidr` to your IP
(`curl -s ifconfig.me`) followed by `/32`.

### 2. Init and plan

```bash
terraform init
terraform plan
```

Expect `Plan: 12 to add`. Find in the output:

- `aws_instance.vm[0]`, `[1]`, `[2]`: the index in brackets comes from `count`.
- `aws_lb_target_group_attachment.web[0..2]`: one per VM.
- `aws_lb.this`: its `dns_name` is `(known after apply)`.

### 3. Apply

```bash
terraform apply
```

The ALB takes 2 to 3 minutes to provision, then its health checks need
another 30 seconds to mark the VMs healthy. Meanwhile look at the outputs:
`vm_availability_zones` should list three different zones.

### 4. Watch the load balancer work

```bash
for i in 1 2 3 4 5 6; do curl -s $(terraform output -raw alb_url) | grep h1; done
```

You should see `VM #0`, `VM #1`, `VM #2` in rotating order. Open the URL in a
browser and refresh.

If you get `503 Service Temporarily Unavailable`, the targets are not healthy
yet. Check in the console: EC2 -> Target Groups -> your group -> *Targets*.
Wait until all three say *healthy*.

### 5. Prove the security group does its job

```bash
curl -m 5 http://$(terraform output -json vm_public_ips | jq -r '.[0]')
```

It times out. Port 80 on the VMs accepts traffic from the ALB's security group
only, not from you. SSH, however, works:

```bash
$(terraform output -json ssh_commands | jq -r '.[0]')
```

The `ssh_commands` output holds one ready-made command per VM, including the
`-i` flag for your private key.

### 6. Break one and watch the ALB route around it

SSH into VM 0 and stop the web server:

```bash
$(terraform output -json ssh_commands | jq -r '.[0]')
sudo systemctl stop nginx
exit
```

Run the `curl` loop from step 4 again. Within about 30 seconds VM #0
disappears from the rotation and only #1 and #2 answer. This is the whole
point of a load balancer plus health checks: a failed backend is removed
automatically, no human involved.

Start it again (`sudo systemctl start nginx`) and watch it return.

### 7. Scale with one number

In `terraform.tfvars` set `vm_count = 2`, run `terraform plan`.
Terraform wants to destroy `aws_instance.vm[2]` and its attachment, and
nothing else. Apply it. Then set it back to 3 and apply again. You just
scaled in and out by editing one line.

### 8. Destroy

```bash
terraform destroy
```

Expect `Resources: 12 destroyed`. Then check the console in the right region:
EC2 -> Instances (all terminated), EC2 -> Load Balancers (empty),
EC2 -> Target Groups (empty).

## How the pieces fit

| Resource                            | Role                                                                 |
|-------------------------------------|----------------------------------------------------------------------|
| `aws_security_group.alb`            | Firewall for the ALB: 80 in from everyone                            |
| `aws_security_group.vm`             | Firewall for VMs: 80 in **only from the ALB's group**, 22 from you   |
| `aws_instance.vm` (`count = 3`)     | The three web servers, one per AZ via `count.index % n`              |
| `aws_lb.this`                       | The load balancer itself, placed in all default subnets              |
| `aws_lb_target_group.web`           | Backend pool + health check definition                               |
| `aws_lb_target_group_attachment.web`| Puts each VM into the pool                                           |
| `aws_lb_listener.http`              | "Port 80 -> forward to the target group"                             |

Things to notice in `main.tf`:

- A security group rule can reference **another security group** instead of a
  CIDR. That is how "only the ALB may talk to the VMs" is expressed.
- `count.index` is used three times: subnet choice, the page text, the tag.
- `aws_instance.vm[*].public_ip` in `outputs.tf` is a *splat*: it collects one
  attribute from every instance into a list.

## Troubleshooting

**`503` from the ALB for more than 3 minutes**
Targets are unhealthy. SSH into a VM and run `systemctl status nginx` and
`cat /var/log/cloud-init-output.log`. Usually `apt-get` was slow on first boot.

**`Error: ... at least two subnets in two different Availability Zones`**
Your default VPC is missing subnets. Easiest fix: VPC console -> Actions ->
*Create default VPC* (after deleting the broken one), or switch region.

**Plan wants to replace VMs after you changed nothing**
Subnet ordering changed. The `sort()` in `locals` prevents this; if you
removed it, put it back.

**`terraform destroy` fails on the security group**
A dependency is still deleting. Wait a minute and run `destroy` again.

## Going further

- Add an `aws_launch_template` and `aws_autoscaling_group` so instances are
  replaced automatically instead of fixed by `count`.
- Terminate a VM in the console by hand, then run `terraform plan`. What does
  Terraform want to do and why?
- Add an HTTPS listener with an ACM certificate (needs a domain you own).
- Turn the VM block into a reusable module and call it from both labs.
