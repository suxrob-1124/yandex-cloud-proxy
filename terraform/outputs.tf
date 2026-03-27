# =============================================================
#  Outputs — values that Terraform exposes externally
#  Used by Makefile to generate Ansible inventory
# =============================================================

output "server_ip" {
  description = "Server public IP"
  value       = yandex_vpc_address.public_ip.external_ipv4_address[0].address
}

output "server_name" {
  description = "VM name"
  value       = yandex_compute_instance.xray.name
}

output "ssh_user" {
  description = "SSH user"
  value       = var.ssh_user
}

output "xray_port" {
  description = "Xray port"
  value       = var.xray_port
}

output "sub_port" {
  description = "Nginx port for configs"
  value       = var.sub_port
}

output "zone" {
  description = "Availability zone"
  value       = var.yc_zone
}

# Convenient output for SSH connection
output "ssh_command" {
  description = "SSH connection command"
  value       = "ssh ${var.ssh_user}@${yandex_vpc_address.public_ip.external_ipv4_address[0].address}"
}

# JSON for generating Ansible inventory via Makefile
output "ansible_inventory_json" {
  description = "JSON for generating Ansible inventory"
  value = jsonencode({
    servers = [
      {
        name     = yandex_compute_instance.xray.name
        ip       = yandex_vpc_address.public_ip.external_ipv4_address[0].address
        ssh_user = var.ssh_user
        sub_port = var.sub_port
      }
    ]
  })
}
