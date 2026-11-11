output "alb_url" {
  description = "Open this in a browser and refresh a few times. Wait 2-3 minutes after apply for health checks to pass."
  value       = "http://${aws_lb.this.dns_name}"
}

output "vm_public_ips" {
  description = "Public IPs of the VMs (for SSH). Note: port 80 on these is NOT open to you, only to the ALB."
  value       = aws_instance.vm[*].public_ip
}

output "vm_availability_zones" {
  description = "Shows the VMs spread across AZs"
  value       = aws_instance.vm[*].availability_zone
}

output "ssh_commands" {
  description = "One ready-made SSH command per VM. The private key is assumed to sit next to the .pub file, without the .pub suffix."
  value       = [for ip in aws_instance.vm[*].public_ip : "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ubuntu@${ip}"]
}
