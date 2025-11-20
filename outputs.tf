output "dns_server_ip" {
  description = "IP адрес DNS сервера"
  value       = var.dns_server_ip
}

output "dns_zone" {
  description = "Настроенная DNS зона"
  value       = var.dns_zone
}

output "tsig_key_name" {
  description = "Имя TSIG ключа"
  value       = var.tsig_key_name
}

output "tsig_secret" {
  description = "TSIG секрет (base64)"
  value       = random_password.tsig_secret.result
  sensitive   = true
}

output "pdns_api_key" {
  description = "PowerDNS API ключ"
  value       = local.pdns_api_key
  sensitive   = true
}

output "vm_id" {
  description = "ID виртуальной машины"
  value       = libvirt_domain.dns_server.id
}

output "vm_name" {
  description = "Имя виртуальной машины"
  value       = libvirt_domain.dns_server.name
}

output "ssh_command" {
  description = "Команда для SSH подключения"
  value       = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${var.dns_server_ip}"
}

output "virsh_console_command" {
  description = "Команда для подключения к консоли через virsh"
  value       = "virsh console ${var.vm_name}"
}

output "pdns_api_url" {
  description = "URL PowerDNS API"
  value       = "http://${var.dns_server_ip}:8081"
}

output "test_dns_command" {
  description = "Команда для тестирования DNS сервера"
  value       = "dig @${var.dns_server_ip} ${var.dns_zone} SOA"
}

output "nsupdate_example" {
  description = "Пример использования nsupdate с TSIG ключом"
  value       = <<-EOT
    # Создать файл с TSIG ключом:
    cat > /tmp/tsig.key <<EOF
    key "${var.tsig_key_name}" {
      algorithm ${var.tsig_algorithm};
      secret "$(terraform output -raw tsig_secret)";
    };
    EOF

    # Обновить TXT запись:
    nsupdate -k /tmp/tsig.key <<EOF
    server ${var.dns_server_ip}
    zone ${var.dns_zone}
    update add _acme-challenge.${var.dns_zone}. 300 IN TXT "test-txt-record"
    send
    EOF

    # Проверить:
    dig @${var.dns_server_ip} _acme-challenge.${var.dns_zone} TXT
  EOT
}
