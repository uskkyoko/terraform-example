#!/usr/bin/env bash
# Builds ansible/inventory.ini from the Terraform outputs of the lab in the
# parent folder. Run it after `terraform apply` and again after any re-apply
# that changed the IP.
set -euo pipefail
cd "$(dirname "$0")/.."

IP=$(terraform output -raw public_ip)
# ssh_command looks like:  ssh -i ~/.ssh/id_ed25519 ubuntu@3.120.xx.xx
KEY=$(terraform output -raw ssh_command | awk '{print $3}')

cat > ansible/inventory.ini <<INV
[web]
${IP} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY}
INV

echo "Wrote ansible/inventory.ini:"
cat ansible/inventory.ini
