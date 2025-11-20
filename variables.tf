variable "vm_name" {
  description = "Имя виртуальной машины DNS-сервера"
  type        = string
  default     = "dns-server"
}

variable "memory" {
  description = "Объем RAM в MB"
  type        = number
  default     = 2048
}

variable "vcpu" {
  description = "Количество vCPU"
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Размер диска в байтах"
  type        = number
  default     = 21474836480 # 20GB
}

variable "dns_zone" {
  description = "DNS зона для управления"
  type        = string
  default     = "example.com"
}

variable "dns_nameservers" {
  description = "Nameservers для cloud-init"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "network_cidr" {
  description = "CIDR сети для DNS сервера"
  type        = string
  default     = "192.168.200.0/24"
}

variable "dns_server_ip" {
  description = "IP адрес DNS сервера"
  type        = string
  default     = "192.168.200.100"
}

variable "ssh_public_key" {
  description = "SSH публичный ключ для доступа"
  type        = string
  default     = ""
}

variable "base_image_url" {
  description = "URL базового образа (Ubuntu/Debian cloud image)"
  type        = string
  default     = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

variable "pdns_api_key" {
  description = "API ключ для PowerDNS (будет сгенерирован если не указан)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tsig_key_name" {
  description = "Имя TSIG ключа"
  type        = string
  default     = "txt-updater"
}

variable "allowed_tsig_operations" {
  description = "Разрешенные операции для TSIG ключа"
  type        = list(string)
  default     = ["UPDATE"]
}

variable "tsig_algorithm" {
  description = "Алгоритм TSIG ключа"
  type        = string
  default     = "hmac-sha256"
}

variable "wg_config" {
  description = "Конфигурация WireGuard туннеля (опционально)"
  type = object({
    enabled     = bool
    private_key = string
    address     = string
    peer_public_key = string
    peer_endpoint   = string
    peer_allowed_ips = list(string)
  })
  default = {
    enabled          = false
    private_key      = ""
    address          = ""
    peer_public_key  = ""
    peer_endpoint    = ""
    peer_allowed_ips = []
  }
  sensitive = true
}

variable "firewall_allowed_sources" {
  description = "Разрешенные источники для DNS запросов (CIDR)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_dnssec" {
  description = "Включить DNSSEC"
  type        = bool
  default     = false
}

variable "pool_name" {
  description = "Имя libvirt storage pool"
  type        = string
  default     = "dns-server-pool"
}

variable "pool_path" {
  description = "Путь к директории storage pool"
  type        = string
  default     = "/var/lib/libvirt/pools/dns-server"
}

variable "libvirt_uri" {
  description = "URI подключения к libvirt"
  type        = string
  default     = "qemu:///system"
}
