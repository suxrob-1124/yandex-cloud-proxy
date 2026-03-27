terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.100"
    }
  }

  # Remote state in YC Object Storage
  # Secrets (access_key, secret_key) are stored in backend.conf
  backend "s3" {
    endpoint = "https://storage.yandexcloud.net"
    bucket   = "xray-tfstate"
    region   = "ru-central1"
    key      = "terraform.tfstate"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "yandex" {
  # Service Account Key — does not expire, for production use
  # Create: yc iam key create --service-account-name xray-terraform --output key.json
  service_account_key_file = var.yc_service_account_key_file

  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}
