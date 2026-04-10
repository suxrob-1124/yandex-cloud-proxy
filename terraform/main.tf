# =============================================================
#  Shared network — one VPC for all servers
# =============================================================

resource "yandex_vpc_network" "main" {
  name        = "edge-network"
  description = "Shared network for edge servers"
}

# =============================================================
#  Subnets — one per server (different CIDR)
# =============================================================

resource "yandex_vpc_subnet" "main" {
  for_each       = var.servers
  name           = "${each.key}-subnet"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [each.value.subnet_cidr]
}

# =============================================================
#  Static public IP — one per server
#  Reserved separately — the address persists when the VM is recreated
# =============================================================

resource "yandex_vpc_address" "public_ip" {
  for_each    = var.servers
  name        = "${each.key}-ip"
  description = "Static IP for ${each.key}"

  external_ipv4_address {
    zone_id = var.yc_zone
  }

  # Protection against accidental deletion
  deletion_protection = true
}

# =============================================================
#  Security group — shared for all servers
# =============================================================

resource "yandex_vpc_security_group" "xray" {
  name        = "edge-sg"
  description = "Access rules for edge servers"
  network_id  = yandex_vpc_network.main.id

  # Outbound traffic — unrestricted
  egress {
    protocol       = "ANY"
    description    = "All outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH — management only
  ingress {
    protocol       = "TCP"
    description    = "SSH access"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  # Xray VLESS+Reality
  ingress {
    protocol       = "TCP"
    description    = "Xray VLESS proxy"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = var.xray_port
  }

  # Nginx — serving client configs
  ingress {
    protocol       = "TCP"
    description    = "Nginx sub configs"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = var.sub_port
  }
}

# =============================================================
#  Virtual machines — one per server
# =============================================================

# Get the latest Ubuntu image from the family
data "yandex_compute_image" "ubuntu" {
  family = var.vm_image_family
}

resource "yandex_compute_instance" "xray" {
  for_each    = var.servers
  name        = each.key
  platform_id = var.vm_platform
  zone        = var.yc_zone

  description = "Xray VLESS+Reality VPN server (${each.key})"

  resources {
    cores         = var.vm_cores
    memory        = var.vm_memory_gb
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.vm_disk_gb
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main[each.key].id
    security_group_ids = [yandex_vpc_security_group.xray.id]

    # Attach static IP
    nat            = true
    nat_ip_address = yandex_vpc_address.public_ip[each.key].external_ipv4_address[0].address
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
  }

  scheduling_policy {
    preemptible = false
  }

  # Do not recreate VM when metadata or boot image changes
  lifecycle {
    ignore_changes = [metadata, boot_disk[0].initialize_params[0].image_id]
  }

  depends_on = [
    yandex_vpc_subnet.main,
    yandex_vpc_security_group.xray,
    yandex_vpc_address.public_ip,
  ]
}
