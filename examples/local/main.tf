terraform {
  required_version = ">= 1.0"
}

# Локальный пример использования DNS модуля с libvirt
module "dns_server" {
  source = "../.."

  # Основные настройки
  vm_name       = "dns-server"
  dns_zone      = "test.local"
  dns_server_ip = "192.168.200.100"
  network_cidr  = "192.168.200.0/24"

  # Ресурсы VM
  memory    = 2048
  vcpu      = 2
  disk_size = 21474836480 # 20GB

  # SSH ключ (замените на свой!)
  ssh_public_key = var.ssh_public_key_content != "" ? var.ssh_public_key_content : file(pathexpand(var.ssh_public_key_path))

  # TSIG настройки
  tsig_key_name  = "txt-updater"
  tsig_algorithm = "hmac-sha256"

  # WireGuard настройки (опционально)
  wg_config = {
    enabled          = false
    private_key      = ""
    address          = ""
    peer_public_key  = ""
    peer_endpoint    = ""
    peer_allowed_ips = []
  }

  # Firewall
  firewall_allowed_sources = ["0.0.0.0/0"]

  # DNSSEC
  enable_dnssec = false

  # Libvirt настройки
  pool_name   = "dns-server-pool"
  pool_path   = "/var/lib/libvirt/pools/dns-server"
  libvirt_uri = "qemu:///system"

  # База образ Ubuntu 22.04
  base_image_url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

# Outputs
output "dns_server_ip" {
  value = module.dns_server.dns_server_ip
}

output "dns_zone" {
  value = module.dns_server.dns_zone
}

output "ssh_command" {
  value = module.dns_server.ssh_command
}

output "virsh_console_command" {
  value = module.dns_server.virsh_console_command
}

output "test_dns_command" {
  value = module.dns_server.test_dns_command
}

output "tsig_key_name" {
  value = module.dns_server.tsig_key_name
}

output "tsig_secret" {
  value     = module.dns_server.tsig_secret
  sensitive = true
}

output "nsupdate_example" {
  value = module.dns_server.nsupdate_example
}

output "pdns_api_url" {
  value = module.dns_server.pdns_api_url
}
