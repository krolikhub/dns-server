provider "libvirt" {
  uri = var.libvirt_uri
}

# Storage pool для виртуальных машин
resource "libvirt_pool" "vm_pool" {
  name = var.pool_name
  type = "dir"
  path = var.pool_path
}

# Генерация TSIG секрета
resource "random_password" "tsig_secret" {
  length  = 32
  special = false
}

# Генерация PowerDNS API ключа
resource "random_password" "pdns_api_key" {
  length  = 32
  special = false
}

locals {
  pdns_api_key = var.pdns_api_key != "" ? var.pdns_api_key : random_password.pdns_api_key.result
  tsig_secret_base64 = base64encode(random_password.tsig_secret.result)
}

# Базовый образ для виртуальной машины
resource "libvirt_volume" "base" {
  name   = "${var.vm_name}-base.qcow2"
  pool   = libvirt_pool.vm_pool.name
  source = var.base_image_url
  format = "qcow2"
}

# Диск для виртуальной машины
resource "libvirt_volume" "dns_server" {
  name           = "${var.vm_name}.qcow2"
  pool           = libvirt_pool.vm_pool.name
  base_volume_id = libvirt_volume.base.id
  size           = var.disk_size
  format         = "qcow2"
}

# Cloud-init диск
resource "libvirt_cloudinit_disk" "cloudinit" {
  name      = "${var.vm_name}-cloudinit.iso"
  pool      = libvirt_pool.vm_pool.name
  user_data = data.template_file.user_data.rendered
}

# Сетевой интерфейс
resource "libvirt_network" "dns_network" {
  name      = "${var.vm_name}-network"
  mode      = "nat"
  domain    = var.dns_zone
  addresses = [var.network_cidr]

  dns {
    enabled = true
  }

  dhcp {
    enabled = false
  }
}

# Виртуальная машина
resource "libvirt_domain" "dns_server" {
  name   = var.vm_name
  memory = var.memory
  vcpu   = var.vcpu

  # Используем QEMU эмуляцию вместо KVM
  type    = "qemu"
  machine = "pc"
  arch    = "x86_64"

  cloudinit = libvirt_cloudinit_disk.cloudinit.id

  network_interface {
    network_id     = libvirt_network.dns_network.id
    addresses      = [var.dns_server_ip]
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.dns_server.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  # Настройки безопасности для решения проблем с правами доступа
  # Отключаем SELinux/AppArmor security labels для предотвращения Permission denied
  xml {
    xslt = <<EOF
<?xml version="1.0" ?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output omit-xml-declaration="yes" indent="yes"/>

  <!-- Копируем все узлы и атрибуты по умолчанию -->
  <xsl:template match="node()|@*">
     <xsl:copy>
       <xsl:apply-templates select="node()|@*"/>
     </xsl:copy>
  </xsl:template>

  <!-- Удаляем все существующие seclabel элементы -->
  <xsl:template match="seclabel"/>

  <!-- Добавляем единственный seclabel с type='none' в domain -->
  <xsl:template match="/domain">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <seclabel type='none' model='none'/>
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
EOF
  }
}

# Cloud-init user data
data "template_file" "user_data" {
  template = file("${path.module}/cloud-init/user-data.yml")

  vars = {
    hostname            = var.vm_name
    dns_zone            = var.dns_zone
    dns_server_ip       = var.dns_server_ip
    pdns_api_key        = local.pdns_api_key
    tsig_key_name       = var.tsig_key_name
    tsig_secret         = local.tsig_secret_base64
    tsig_algorithm      = var.tsig_algorithm
    ssh_public_key      = var.ssh_public_key
    wg_enabled          = var.wg_config.enabled
    wg_private_key      = var.wg_config.private_key
    wg_address          = var.wg_config.address
    wg_peer_public_key  = var.wg_config.peer_public_key
    wg_peer_endpoint    = var.wg_config.peer_endpoint
    wg_peer_allowed_ips = join(",", var.wg_config.peer_allowed_ips)
    enable_dnssec       = var.enable_dnssec
  }
}
