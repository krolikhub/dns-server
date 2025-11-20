# DNS Server Terraform Module

Terraform модуль для развертывания DNS сервера на базе PowerDNS с поддержкой динамического обновления (RFC-2136) через TSIG ключи.

## Возможности

- ✅ **PowerDNS** - современный авторитативный DNS сервер
- ✅ **RFC-2136** - динамическое обновление DNS записей
- ✅ **TSIG аутентификация** - безопасное обновление с ограниченными правами на TXT записи
- ✅ **Firewall** - автоматическая настройка UFW (разрешены порты 53 tcp/udp)
- ✅ **WireGuard** - опциональная поддержка VPN туннелей
- ✅ **PowerDNS API** - REST API для управления зонами
- ✅ **Cloud-init** - автоматическая настройка при первом запуске
- ✅ **Локальная разработка** - поддержка libvirt/KVM для тестирования

## Структура проекта

```
dns-server/
├── main.tf                 # Основная конфигурация terraform
├── variables.tf            # Переменные модуля
├── outputs.tf              # Выходные данные модуля
├── versions.tf             # Версии провайдеров
├── cloud-init/
│   └── user-data.yml       # Cloud-init конфигурация
├── scripts/
│   ├── test-dns-update.sh  # Тест динамического обновления DNS
│   ├── get-tsig-info.sh    # Получение TSIG информации
│   └── check-dns-status.sh # Проверка статуса DNS сервера
└── examples/
    └── local/              # Пример для локальной разработки
        ├── main.tf
        └── README.md
```

## Быстрый старт (локально с libvirt)

### 1. Установка зависимостей

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

# Включение libvirt
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Добавление пользователя в группу
sudo usermod -a -G libvirt $(whoami)
newgrp libvirt

# Установка Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Генерация SSH ключа (если нужно)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

### 2. Запуск

```bash
cd examples/local

# Инициализация
terraform init

# Применение
terraform apply
```

### 3. Проверка

```bash
# Получить IP адрес
virsh domifaddr dns-server

# Проверить DNS
dig @192.168.122.100 test.local SOA

# Подключиться по SSH
ssh root@192.168.122.100
```

## Использование модуля

### Базовый пример

```hcl
module "dns_server" {
  source = "git::https://github.com/yourusername/dns-server.git"

  vm_name       = "dns-server"
  dns_zone      = "example.com"
  dns_server_ip = "192.168.122.100"

  ssh_public_key = file("~/.ssh/id_rsa.pub")

  tsig_key_name  = "txt-updater"
  tsig_algorithm = "hmac-sha256"
}
```

### Пример с WireGuard

```hcl
module "dns_server" {
  source = "git::https://github.com/yourusername/dns-server.git"

  vm_name       = "dns-server"
  dns_zone      = "example.com"
  dns_server_ip = "192.168.122.100"

  ssh_public_key = file("~/.ssh/id_rsa.pub")

  # WireGuard конфигурация
  wg_config = {
    enabled          = true
    private_key      = file("wg-private.key")
    address          = "10.0.0.2/24"
    peer_public_key  = "PEER_PUBLIC_KEY_HERE"
    peer_endpoint    = "vpn.example.com:51820"
    peer_allowed_ips = ["10.0.0.0/24"]
  }
}
```

## Работа с TSIG ключами

### Получение TSIG секрета

```bash
# Из terraform outputs
terraform output -raw tsig_secret

# Через скрипт
./scripts/get-tsig-info.sh
```

### Использование nsupdate

```bash
# Создать файл с ключом
TSIG_SECRET=$(terraform output -raw tsig_secret)
cat > /tmp/tsig.key <<EOF
key "txt-updater" {
  algorithm hmac-sha256;
  secret "$TSIG_SECRET";
};
EOF

# Добавить TXT запись
nsupdate -k /tmp/tsig.key <<EOF
server 192.168.122.100
zone test.local
update add _acme-challenge.test.local. 300 IN TXT "verification-string"
send
EOF

# Проверить
dig @192.168.122.100 _acme-challenge.test.local TXT
```

### Автоматическое тестирование

```bash
# Запустить тест обновления DNS
TSIG_SECRET=$(terraform output -raw tsig_secret) ./scripts/test-dns-update.sh
```

## PowerDNS API

### Получение API ключа

```bash
PDNS_API_KEY=$(terraform output -raw pdns_api_key)
```

### Примеры использования API

```bash
# Список зон
curl -H "X-API-Key: $PDNS_API_KEY" \
  http://192.168.122.100:8081/api/v1/servers/localhost/zones

# Информация о зоне
curl -H "X-API-Key: $PDNS_API_KEY" \
  http://192.168.122.100:8081/api/v1/servers/localhost/zones/test.local

# Статистика
curl -H "X-API-Key: $PDNS_API_KEY" \
  http://192.168.122.100:8081/api/v1/servers/localhost/statistics
```

## Интеграция с Vault (планируется)

Для хранения TSIG ключей и WireGuard конфигурации в HashiCorp Vault:

```hcl
# Получение TSIG секрета из Vault
data "vault_generic_secret" "tsig" {
  path = "secret/dns/tsig"
}

module "dns_server" {
  source = "./dns-server"

  # ... другие параметры ...

  # TSIG из Vault
  tsig_key_name  = data.vault_generic_secret.tsig.data["key_name"]

  # WireGuard из Vault
  wg_config = {
    enabled     = true
    private_key = data.vault_generic_secret.wg.data["private_key"]
    # ... остальные параметры ...
  }
}
```

## Полезные команды

### Управление VM

```bash
# Список VM
virsh list --all

# Информация о VM
virsh dominfo dns-server

# IP адрес VM
virsh domifaddr dns-server

# Консоль VM
virsh console dns-server

# Остановка VM
virsh shutdown dns-server

# Удаление VM
virsh destroy dns-server
virsh undefine dns-server
```

### Проверка DNS сервера

```bash
# Статус DNS сервера
./scripts/check-dns-status.sh

# Проверка записей
dig @192.168.122.100 test.local SOA
dig @192.168.122.100 test.local NS
dig @192.168.122.100 ns1.test.local A
```

### Отладка на сервере

```bash
# Подключение
ssh root@192.168.122.100

# Статус PowerDNS
systemctl status pdns

# Логи PowerDNS
journalctl -u pdns -f

# Логи cloud-init
tail -f /var/log/cloud-init-output.log

# Проверка БД PowerDNS
sqlite3 /var/lib/powerdns/pdns.sqlite3 "SELECT * FROM domains;"
sqlite3 /var/lib/powerdns/pdns.sqlite3 "SELECT * FROM records;"
sqlite3 /var/lib/powerdns/pdns.sqlite3 "SELECT * FROM tsigkeys;"

# Статус firewall
ufw status verbose

# Проверка WireGuard (если включен)
wg show
```

## Переменные

| Переменная | Описание | Тип | По умолчанию |
|------------|----------|-----|--------------|
| `vm_name` | Имя VM | string | "dns-server" |
| `memory` | RAM в MB | number | 2048 |
| `vcpu` | Количество vCPU | number | 2 |
| `disk_size` | Размер диска в байтах | number | 21474836480 (20GB) |
| `dns_zone` | DNS зона | string | "example.com" |
| `dns_server_ip` | IP адрес DNS сервера | string | "192.168.122.100" |
| `ssh_public_key` | SSH публичный ключ | string | "" |
| `tsig_key_name` | Имя TSIG ключа | string | "txt-updater" |
| `tsig_algorithm` | Алгоритм TSIG | string | "hmac-sha256" |
| `wg_config` | Конфигурация WireGuard | object | disabled |
| `enable_dnssec` | Включить DNSSEC | bool | false |

Полный список переменных смотрите в [variables.tf](variables.tf).

## Outputs

| Output | Описание |
|--------|----------|
| `dns_server_ip` | IP адрес DNS сервера |
| `dns_zone` | Настроенная DNS зона |
| `tsig_key_name` | Имя TSIG ключа |
| `tsig_secret` | TSIG секрет (sensitive) |
| `pdns_api_key` | PowerDNS API ключ (sensitive) |
| `ssh_command` | Команда для SSH подключения |
| `nsupdate_example` | Пример использования nsupdate |

## Использование для Let's Encrypt (ACME DNS-01)

Этот DNS сервер отлично подходит для автоматического получения сертификатов Let's Encrypt через DNS-01 challenge:

```bash
# Пример с certbot
certbot certonly \
  --manual \
  --preferred-challenges dns \
  --manual-auth-hook /path/to/auth-hook.sh \
  --manual-cleanup-hook /path/to/cleanup-hook.sh \
  -d example.com
```

Где `auth-hook.sh`:
```bash
#!/bin/bash
nsupdate -k /etc/letsencrypt/tsig.key <<EOF
server 192.168.122.100
zone example.com
update add _acme-challenge.example.com. 300 IN TXT "$CERTBOT_VALIDATION"
send
EOF
sleep 10
```

## Roadmap

- [ ] Поддержка Selectel Cloud провайдера
- [ ] Поддержка Yandex Cloud провайдера
- [ ] Интеграция с HashiCorp Vault
- [ ] DNSSEC поддержка
- [ ] Мониторинг (Prometheus metrics)
- [ ] Репликация DNS зон (master-slave)
- [ ] Автоматическое резервное копирование

## Требования

- Terraform >= 1.0
- libvirt (для локальной разработки)
- Linux хост с KVM поддержкой

## Лицензия

MIT

## Поддержка

Если у вас возникли проблемы или вопросы:

1. Проверьте [examples/local/README.md](examples/local/README.md)
2. Запустите `./scripts/check-dns-status.sh`
3. Проверьте логи: `journalctl -u pdns` на сервере
4. Создайте issue в GitHub

## Авторы

Создано для упрощения развертывания DNS серверов с динамическим обновлением.
