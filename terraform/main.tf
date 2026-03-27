# =============================================================
#  Network
# =============================================================

resource "yandex_vpc_network" "main" {
  name        = "${var.vm_name}-network"
  description = "Network for the server"
}

resource "yandex_vpc_subnet" "main" {
  name           = "${var.vm_name}-subnet"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidr]
}

# =============================================================
#  Static public IP
#  Reserved separately — the address persists when the VM is recreated
# =============================================================

resource "yandex_vpc_address" "public_ip" {
  name        = "${var.vm_name}-ip"
  description = "Static IP for the server"

  external_ipv4_address {
    zone_id = var.yc_zone
  }

  # Protection against accidental deletion
  deletion_protection = true
}

# =============================================================
#  Security group
#  Least privilege principle — only required ports are opened
# =============================================================

resource "yandex_vpc_security_group" "xray" {
  name        = "${var.vm_name}-sg"
  description = "Server access rules"
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
#  Virtual machine
# =============================================================

# Get the latest Ubuntu image from the family
data "yandex_compute_image" "ubuntu" {
  family = var.vm_image_family
}

resource "yandex_compute_instance" "xray" {
  name        = var.vm_name
  platform_id = var.vm_platform
  zone        = var.yc_zone

  description = "Xray VLESS+Reality VPN server"

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
    subnet_id          = yandex_vpc_subnet.main.id
    security_group_ids = [yandex_vpc_security_group.xray.id]

    # Attach static IP
    nat                = true
    nat_ip_address     = yandex_vpc_address.public_ip.external_ipv4_address[0].address
  }

  metadata = {
    # SSH key for access
    ssh-keys  = "${var.ssh_user}:${file(var.ssh_public_key_path)}"

    # serial-port-enable = 1  # uncomment for debugging via YC console
  }

  # Scheduled maintenance policy
  scheduling_policy {
    preemptible = false
  }

  # Do not recreate VM when metadata changes
  lifecycle {
    ignore_changes = [metadata]
  }

  # Wait for network to be ready
  depends_on = [
    yandex_vpc_subnet.main,
    yandex_vpc_security_group.xray,
    yandex_vpc_address.public_ip,
  ]
}
