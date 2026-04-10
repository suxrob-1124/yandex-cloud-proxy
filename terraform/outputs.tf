# =============================================================
#  Outputs — values that Terraform exposes externally
#  Used by Makefile to generate Ansible inventory
# =============================================================

output "server_ips" {
  description = "Map of server name → public IP"
  value       = { for name, _ in var.servers : name => yandex_vpc_address.public_ip[name].external_ipv4_address[0].address }
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

# JSON for generating Ansible inventory via Makefile
output "ansible_inventory_json" {
  description = "JSON for generating Ansible inventory"
  value = jsonencode({
    servers = [
      for name, cfg in var.servers : {
        name            = name
        ip              = yandex_vpc_address.public_ip[name].external_ipv4_address[0].address
        ssh_user        = var.ssh_user
        sub_port        = var.sub_port
        masquerade_host = cfg.masquerade_host
      }
    ]
  })
}
