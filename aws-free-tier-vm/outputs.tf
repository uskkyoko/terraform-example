output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.vm.id
}

output "public_ip" {
  description = "Public IPv4 address of the VM"
  value       = aws_instance.vm.public_ip
}

output "ami_used" {
  description = "The AMI that was selected"
  value       = "${data.aws_ami.ubuntu.id} (${data.aws_ami.ubuntu.name})"
}

output "ssh_command" {
  description = "Copy-paste this to log in. The private key is assumed to sit next to the .pub file, without the .pub suffix."
  value       = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ubuntu@${aws_instance.vm.public_ip}"
}

output "web_url" {
  description = "Open this in a browser (give the VM ~1 minute after creation)"
  value       = "http://${aws_instance.vm.public_ip}"
}
