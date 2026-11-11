# Terraform lab: a free-tier VM on AWS

In this lab you will use Terraform to create one small Linux virtual machine
(an EC2 instance) on AWS, log in to it, open a web page it serves, change it,
and finally destroy it. Everything stays inside the AWS Free Tier **as long as
you follow the cleanup steps at the end**.

Time needed: 60 to 90 minutes.


## What you will build

```
Your laptop                       AWS (one region)
+------------------+              +----------------------------------------+
| terraform CLI    |  --API-->    | default VPC                            |
| aws CLI          |              |  +----------------------------------+  |
| ~/.ssh/id_ed25519|              |  | security group: 22 (SSH), 80 (HTTP)|  |
+------------------+              |  |  +----------------------------+  |  |
        |                         |  |  | EC2 t3.micro, Ubuntu 24.04 |  |  |
        |  ssh / http             |  |  | nginx -> "Hello from TF"   |  |  |
        +------------------------>|  |  +----------------------------+  |  |
                                  |  +----------------------------------+  |
                                  +----------------------------------------+
```

Terraform creates three things: an SSH key pair, a security group (firewall),
and the instance. It *reads* (but does not create) the default VPC, its subnets,
and the latest Ubuntu image.

## Quick start: every command in order

The full walkthrough is below. If you just want the commands, run these from
the `aws-free-tier-vm` folder, top to bottom.

```bash
# 0. Prerequisites (once per laptop)
terraform -version                      # need >= 1.5
aws --version
aws configure                           # access key, secret, region (e.g. eu-central-1), json
aws sts get-caller-identity             # must print your account ID
ls ~/.ssh/*.pub                         # need one public key; if none:
ssh-keygen -t ed25519 -C "student"      #   creates ~/.ssh/id_ed25519.pub

# 1. Configure
cd aws-free-tier-vm
cp terraform.tfvars.example terraform.tfvars
curl -s ifconfig.me                     # your public IP, for ssh_allowed_cidr
aws configure get region                # put this value in terraform.tfvars as aws_region (REQUIRED)
#    edit terraform.tfvars: aws_region, ssh_public_key_path, ssh_allowed_cidr = "<ip>/32"

# 2. Create the VM
terraform init                          # download the AWS provider
terraform fmt                           # tidy formatting (optional)
terraform validate                      # syntax check, no AWS calls
terraform plan                          # expect: 3 to add, 0 to change, 0 to destroy
terraform apply                         # type yes; ~30 s

# 3. Use the VM (wait ~1 min for nginx to install)
terraform output                        # instance_id, public_ip, ssh_command, web_url
curl $(terraform output -raw web_url)   # <h1>Hello from Terraform!</h1>
$(terraform output -raw ssh_command)    # log in as ubuntu; or:
ssh -i ~/.ssh/<your-key> ubuntu@$(terraform output -raw public_ip)
#    on the VM:  cat /var/log/cloud-init-output.log ; exit

# 4. Inspect state
terraform state list
terraform state show aws_instance.vm
terraform plan                          # expect: No changes.

# 5. Change something, then re-plan and re-apply
#    edit main.tf (user_data text -> replacement; add a tag -> in-place update)
terraform plan
terraform apply

# 6. Destroy everything (do not skip; this is what keeps it free)
terraform destroy                       # type yes; expect: 3 destroyed
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output table
aws ec2 describe-volumes --query 'Volumes[].VolumeId' --output table   # should be empty
aws ec2 describe-addresses --query 'Addresses[].PublicIp' --output table # should be empty
```

## Read this first: what "free" means on AWS

AWS changed its Free Tier on 15 July 2025. Which rules apply to you depends on
**when your account was created**. Check in the AWS console under
*Billing and Cost Management -> Free Tier*.

| Account created        | What you get for EC2                                                                           |
|------------------------|-----------------------------------------------------------------------------------------------|
| Before 15 July 2025    | 12 months of 750 hours/month of t2.micro or t3.micro, 30 GB of EBS storage, 750 h of public IPv4 |
| On/after 15 July 2025  | A credit balance (up to USD 200, some of it unlocked by completing activities) valid for 6 months on the Free plan. EC2 usage is paid from those credits. |

Rules that keep this lab free under either model:

- **One instance at a time**, type `t3.micro` (or `t2.micro`). The `instance_type`
  variable refuses anything else.
- **Destroy it when you are done.** 750 hours is one instance running all month.
  Two instances, or forgetting one for a few weeks, is what produces a bill.
- Root disk is 8 GB gp3 (limit is 30 GB).
- Public IPv4 addresses cost about USD 0.005/hour outside the free allowance.
  Our instance has one. Again: destroy when done.
- Data transfer out is free up to 100 GB/month. A few web page loads are nothing.

**Set up a billing alert before you start** (AWS console -> Billing -> Budgets ->
Create budget -> *Zero spend budget*). It emails you the moment anything is
charged. This takes two minutes and is the best habit you will learn today.

## Prerequisites

1. **An AWS account.** Do not use the root user for daily work. Create an IAM
   user (or, better, an IAM Identity Center user) with the
   `AmazonEC2FullAccess` policy and create an access key for it.
2. **AWS CLI** installed: `aws --version`.
3. **Terraform >= 1.5** installed: `terraform -version`.
   macOS: `brew install terraform`. Others: https://developer.hashicorp.com/terraform/install
4. **An SSH key pair on your laptop.** See the next section; it takes two
   minutes and you need it before `terraform apply`.

## SSH keys: what they are and what to do with yours

Logging in to a Linux VM in the cloud is done with an **SSH key pair**, not a
password:

- the **private key** (file without extension, e.g. `~/.ssh/id_ed25519`) stays
  on your laptop. It is your identity. Treat it like a password.
- the **public key** (same name plus `.pub`) can be given to anyone. Terraform
  uploads it to AWS, and AWS copies it onto the VM at first boot.

When you run `ssh`, your laptop proves it holds the private key that matches
the public key on the VM. Nothing secret is sent over the network.

### 1. Do you already have a key?

```bash
ls ~/.ssh/*.pub
```

- **Nothing listed**: go to step 2 and create one.
- **You see `id_ed25519.pub`**: you are done, the lab uses that path by default.
- **You see other `.pub` files** (for example one you use for GitHub or a
  server): you may reuse one. Tell Terraform which, in `terraform.tfvars`:

  ```hcl
  ssh_public_key_path = "~/.ssh/my_other_key.pub"
  ```

  Only the `.pub` file is read. The private key next to it is never read by
  Terraform.

### 2. Create a key (if you have none)

```bash
ssh-keygen -t ed25519 -C "terraform-lab"
```

Press Enter to accept the default location `~/.ssh/id_ed25519`. You will be
asked for a passphrase. A passphrase protects the key if your laptop is stolen;
you will have to type it at every `ssh` unless you use an agent (see below).
Leaving it empty is acceptable for a lab key you will delete afterwards.

Windows: run the same command in PowerShell (OpenSSH is built in since
Windows 10). The key lands in `C:\Users\<you>\.ssh\`. In `terraform.tfvars`
write the path with forward slashes: `"C:/Users/<you>/.ssh/id_ed25519.pub"`.

Check the result:

```bash
ls -l ~/.ssh/id_ed25519*     # two files: private (no extension) and .pub
cat ~/.ssh/id_ed25519.pub    # starts with "ssh-ed25519 AAAA..."; this is what AWS gets
```

### 3. Connect after `terraform apply`

The `ssh_command` output already contains the right flags. Copy-paste it:

```bash
terraform output -raw ssh_command
# e.g.  ssh -i ~/.ssh/id_ed25519 ubuntu@3.120.xx.xx
```

`-i` tells ssh which private key to use. The user is **`ubuntu`** on Ubuntu
images (it would be `ec2-user` on Amazon Linux). The first time you connect,
ssh asks whether to trust the host; answer `yes`.

If you do not want to type a passphrase every time, load the key into the
agent once per session:

```bash
ssh-add ~/.ssh/id_ed25519
```

### 4. Rules

- **Never commit keys to git, neither private nor public.** Keep them in
  `~/.ssh`, never copy them into the project folder. The `.gitignore` here
  blocks `*.pub`, `*.pem`, `*.key` and `id_*` as a safety net, but a key in a
  pushed repository must be considered compromised: delete it and make a new one.
- **Never** share, email or paste a private key anywhere, including chat with
  your instructor. If asked for "your key", it is always the `.pub` file.
- Private key file permissions must be `600` (`-rw-------`). If ssh complains
  "UNPROTECTED PRIVATE KEY FILE", run `chmod 600 ~/.ssh/id_ed25519`.
- Lost the private key? You cannot recover it and AWS cannot help. Create a
  new pair, update `ssh_public_key_path`, and `terraform apply`. The key pair
  resource and the instance will be **replaced** (new VM, new IP).
- Changing the key on an existing VM without recreating it is possible by
  hand (edit `~/.ssh/authorized_keys` on the VM) but is out of scope here.

### What Terraform does with the key

```hcl
resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))   # reads ONLY the .pub file
}

resource "aws_instance" "vm" {
  key_name = aws_key_pair.this.key_name   # AWS puts the public key on the VM at boot
  # ...
}
```

The public key ends up in the Terraform state file as plain text. That is fine
because it is public. A private key would not be, which is one reason this lab
never generates keys inside Terraform.

## Step 1. Give Terraform your AWS credentials

```bash
aws configure
```

Enter the access key ID, the secret key, a default region such as
`eu-central-1`, and output format `json`. Verify it works:

```bash
aws sts get-caller-identity
```

You should see your account ID and user ARN. Terraform's AWS provider reads
the same credentials file, so no keys go into the `.tf` files. **Never paste
access keys into Terraform code or commit them to git.**

## Step 2. Configure the lab

```bash
cd aws-free-tier-vm
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and:

- set `aws_region` to the region you chose in `aws configure` (check with
  `aws configure get region`). **This value is required**: the variable has
  no default, so if you leave it out Terraform stops and asks
  `var.aws_region  Enter a value:` on every `plan`, `apply` and `destroy`.
  The region decides where your VM physically runs and where you must look
  for it in the console;
- optionally set `ssh_allowed_cidr` to your own IP, found with `curl -s ifconfig.me`,
  followed by `/32`. Leaving `0.0.0.0/0` works but lets the whole internet
  knock on port 22.

## Step 3. Initialise

```bash
terraform init
```

Terraform downloads the AWS provider into `.terraform/` and writes
`.terraform.lock.hcl`, which pins the exact provider version. Both are
git-ignored here. Run `init` again any time you add a provider or module.

## Step 4. Plan

```bash
terraform plan
```

Read the output. You should see `Plan: 3 to add, 0 to change, 0 to destroy.`
Find the three `+` resources. Notice values shown as `(known after apply)`:
Terraform cannot know the public IP until AWS hands one out.

## Step 5. Apply

```bash
terraform apply
```

Type `yes`. It takes about 30 seconds. At the end Terraform prints the outputs:

```
public_ip   = "3.120.xx.xx"
ssh_command = "ssh ubuntu@3.120.xx.xx"
web_url     = "http://3.120.xx.xx"
```

Wait about a minute for the first-boot script to install nginx, then:

```bash
curl $(terraform output -raw web_url)
```

You should get `<h1>Hello from Terraform!</h1>`. Open the same URL in a browser.

Log in (the output already includes `-i <your private key>`):

```bash
$(terraform output -raw ssh_command)
```

Type `yes` to accept the host key. If you get `Permission denied (publickey)`,
read the SSH keys section above. On the VM, try `cat /var/log/cloud-init-output.log`
to see what the first-boot script did, then `exit`.

## Step 6. Explore the state

```bash
terraform state list                 # what Terraform is managing
terraform state show aws_instance.vm # every attribute of the VM
terraform output                     # just the outputs again
terraform plan                       # should say: No changes.
```

"No changes" is the key idea: Terraform compared the real infrastructure with
your files and found them identical. Running `apply` twice is safe.

## Step 7. Change something

Edit `main.tf` and change the text inside the `user_data` block, for example
`Hello from <your name>!`. Run `terraform plan`.

Terraform wants to **destroy and recreate** the instance (look for `-/+` and
`# forces replacement`). The first-boot script only runs at first boot, so a
new VM is the only way to apply it. This is a deliberate lesson: some changes
are in-place updates, some force replacement. Apply it, wait a minute, `curl`
the new IP (it changes!).

Now try a change that does *not* force replacement: in `main.tf` add a tag,
for example `Owner = "your-name"`, next to `Name`. `terraform plan` shows `~`
(update in place). Apply it.

## Step 8. Destroy

```bash
terraform destroy
```

Type `yes`. Then **verify in the AWS console** (EC2 -> Instances, correct
region) that the instance shows *terminated* and that no other instance is
running. The key pair and security group are gone too.

Lastly, in the EC2 console check *Elastic Block Store -> Volumes* and
*Network and Security -> Elastic IPs*. Both should be empty. This lab does not
create either, but checking is the habit.

## Cleanup checklist

- [ ] `terraform destroy` finished with `Destroy complete! Resources: 3 destroyed.`
- [ ] EC2 console shows no running instances in **every region you used**
- [ ] No volumes, no Elastic IPs
- [ ] Zero-spend budget alert exists
- [ ] (Optional) deactivate the IAM access key if you will not use it again

## File-by-file

| File                       | Purpose                                                         |
|----------------------------|-----------------------------------------------------------------|
| `versions.tf`              | Required Terraform and provider versions                        |
| `providers.tf`             | Region and default tags for the AWS provider                    |
| `variables.tf`             | Inputs with defaults and a free-tier guard on `instance_type`   |
| `main.tf`                  | Data sources (VPC, subnets, AMI) and the three resources        |
| `outputs.tf`               | Values printed after apply (IP, SSH command, URL)               |
| `terraform.tfvars.example` | Template for your own values; copy to `terraform.tfvars`        |
| `.gitignore`               | Keeps state, lock file, tfvars, inventory and keys out of git   |
| `ansible/`                 | Playbook, template, config and inventory helper for the homework |

## Troubleshooting

**Terraform asks `var.aws_region  Enter a value:`**
You have no `terraform.tfvars`, or it lacks `aws_region`. Copy the example
file and set the region. Typing it at the prompt works too, but you will be
asked again on the next command. Alternative: `terraform plan -var aws_region=eu-central-1`.

**`Error: Invalid value for variable ... Must look like a real AWS region`**
Typo in `aws_region`. Valid examples: `eu-central-1`, `us-east-1`, `eu-west-2`.
List them all with `aws ec2 describe-regions --query 'Regions[].RegionName' --output text`.

**`Error: no matching EC2 VPC found`**
Your account has no default VPC in this region. In the console go to
VPC -> Your VPCs -> Actions -> *Create default VPC*, then re-run.

**`Error: Invalid function argument ... file(...)`**
The public key path in `ssh_public_key_path` does not exist. Run `ssh-keygen`
(see Prerequisites) or point the variable at your existing `.pub` file.

**`UnauthorizedOperation`**
Your IAM user lacks EC2 permissions. Attach `AmazonEC2FullAccess` or ask the
instructor.

**`InvalidParameterValue: The requested configuration is currently not supported`**
`t3.micro` is not available in that availability zone or region. Set
`instance_type = "t2.micro"` or switch region.

**The web page does not load**
Wait 1 to 2 minutes; the script installs packages on first boot. If it still
fails, SSH in and check `cat /var/log/cloud-init-output.log`.

**`Permission denied (publickey)` on SSH**
The user is `ubuntu`, not `root` or `ec2-user`. Make sure you are using the
private key that matches the uploaded `.pub`: `ssh -i ~/.ssh/id_ed25519 ubuntu@IP`.
Compare fingerprints: `ssh-keygen -lf ~/.ssh/id_ed25519.pub` locally versus
EC2 console -> Key Pairs -> `tf-student-demo-key`. If they differ, you
uploaded a different key than the one you are logging in with.

**SSH hangs / times out**
If you set `ssh_allowed_cidr` to your IP, your IP may have changed. Check
`curl -s ifconfig.me`, update `terraform.tfvars`, `terraform apply`.

**Terraform says resources exist but the console is empty (or vice versa)**
You are probably looking at a different region in the console. Check the
region selector in the top right corner.

## Using this lab for the Week 11 homework

The homework asks for: a Terraform configuration with at least two AWS
resources, an annotated `terraform plan`, an idempotency proof for Terraform,
an Ansible playbook run twice, and a `terraform destroy` confirmation. This lab
produces all of it. Work through it in this order.

### 0. Get the latest version of this repository

This repository is updated between sessions: bugs get fixed, instructions get
clarified, and the Ansible part was added after the first lab. **Always start
from the latest version**, otherwise you may fight a problem that is already
solved, or miss a file the homework needs.

You will submit a link to **your own** GitHub repository, so fork first:

1. On GitHub, open https://github.com/rtym/terraform-example and press *Fork*.
2. Clone your fork and register the original as `upstream`:

   ```bash
   git clone git@github.com:<your-github-user>/terraform-example.git
   cd terraform-example
   git remote add upstream https://github.com/rtym/terraform-example.git
   ```

3. **Before every work session**, pull the latest changes from the original:

   ```bash
   git fetch upstream
   git merge upstream/main          # or: git rebase upstream/main
   ```

   If you cloned earlier without forking, `git pull` inside the folder is enough
   to get the latest version, but you still need your own fork to submit.

Check you are up to date: `git log -1 --format='%h %cd'` should show a recent
date, and `ls aws-free-tier-vm/ansible/` must list `playbook.yml`.

### 1. Terraform: plan, apply, prove idempotency

```bash
cd aws-free-tier-vm
cp terraform.tfvars.example terraform.tfvars    # set region and key path
terraform init
terraform plan -no-color > plan-1.txt           # deliverable: annotated plan
terraform apply                                 # yes
terraform plan -no-color > plan-2.txt           # deliverable: "No changes."
```

Annotate `plan-1.txt` in your submission. The symbols Terraform uses:

| Symbol | Meaning                                  | When you see it in this lab                                       |
|--------|------------------------------------------|-------------------------------------------------------------------|
| `+`    | create                                   | First plan: key pair, security group, instance                    |
| `~`    | update in place                          | After adding a tag to the instance                                |
| `-/+`  | destroy then create (replacement)        | After editing `user_data`; the old VM is destroyed first          |
| `+/-`  | create then destroy (replacement)        | Same, but with `create_before_destroy` set                        |
| `-`    | destroy                                  | `terraform destroy`, or removing a resource from the code         |
| `<=`   | read (data source) during apply          | If a data source cannot be resolved at plan time                  |

`plan-2.txt` must say `No changes. Your infrastructure matches the
configuration.` That line is the Terraform idempotency proof.

### 2. Ansible: configure the VM, run twice

Install Ansible on your laptop if needed (`pip install ansible` or
`brew install ansible`), then:

```bash
./ansible/make-inventory.sh                     # reads IP and key from terraform output
cd ansible
ansible all -m ping                             # expect "pong"
ansible-playbook playbook.yml | tee run-1.txt   # deliverable: some "changed"
ansible-playbook playbook.yml | tee run-2.txt   # deliverable: changed=0
curl http://$(cd .. && terraform output -raw public_ip)
cd ..
```

Look at the `PLAY RECAP` line of each run. Run 2 must show `changed=0`. That
is the Ansible idempotency proof. Edit `student_name` in `playbook.yml`, run
again, and explain in one sentence why exactly one task changed.

### 3. Destroy and confirm

```bash
terraform destroy -no-color | tee destroy.txt   # yes; deliverable: "Resources: 3 destroyed."
aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text
```

The second command must print nothing. Include both in the submission.

### 4. Submit

Commit your `.tf` files, the `ansible/` folder, `plan-1.txt`, `plan-2.txt`,
`run-1.txt`, `run-2.txt` and `destroy.txt`, push to your fork and submit the
repository link in Canvas.

**Do not commit** `terraform.tfstate*`, `terraform.tfvars`,
`ansible/inventory.ini`, or any SSH key, public or private. The `.gitignore`
blocks them, but check `git status` before you push. If a private key ever
lands in a repository, consider it compromised: delete it, create a new pair.

## Going further

- Pin a specific AMI ID instead of `most_recent = true` and discuss why
  production teams do that.
- Replace the default VPC with your own `aws_vpc`, `aws_subnet`,
  `aws_internet_gateway` and `aws_route_table`.
- Move the state to an S3 bucket (`backend "s3"`) and discuss remote state.
- Run `terraform plan` from a second laptop with the same code and no state
  file. What does it want to do, and why is that dangerous?

## References

- AWS Free Tier: https://aws.amazon.com/free/
- Terraform AWS provider docs: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- Terraform CLI docs: https://developer.hashicorp.com/terraform/cli
- Ubuntu AMI locator: https://cloud-images.ubuntu.com/locator/ec2/
