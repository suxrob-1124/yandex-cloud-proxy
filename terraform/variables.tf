# =============================================================
#  Yandex Cloud — required variables
#  Values are set in terraform.tfvars (do not commit to git!)
# =============================================================

variable "yc_service_account_key_file" {
  description = "Path to the service account JSON key. Create: yc iam key create --service-account-name xray-terraform --output key.json"
  type        = string
}

variable "yc_cloud_id" {
  description = "Cloud ID. Get: yc resource-manager cloud list"
  type        = string
}

variable "yc_folder_id" {
  description = "Folder ID. Get: yc resource-manager folder list"
  type        = string
}

variable "yc_zone" {
  description = "Availability zone"
  type        = string
  default     = "ru-central1-a"
}

# =============================================================
#  Network
# =============================================================

variable "subnet_cidr" {
  description = "Subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

# =============================================================
#  VM
# =============================================================

variable "vm_name" {
  description = "Virtual machine name"
  type        = string
  default     = "edge-01"
}

variable "vm_cores" {
  description = "Number of vCPUs"
  type        = number
  default     = 2
}

variable "vm_memory_gb" {
  description = "RAM size in GB"
  type        = number
  default     = 2
}

variable "vm_disk_gb" {
  description = "Disk size in GB"
  type        = number
  default     = 20
}

variable "vm_image_family" {
  description = "OS image family"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "vm_platform" {
  description = "VM platform"
  type        = string
  default     = "standard-v3"
}

# =============================================================
#  SSH access
# =============================================================

variable "ssh_user" {
  description = "User for SSH connection"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# =============================================================
#  Service ports
# =============================================================

variable "xray_port" {
  description = "Xray port (VLESS)"
  type        = number
  default     = 443
}

variable "sub_port" {
  description = "Nginx port for serving configs"
  type        = number
  default     = 8443
}
