# Локальный пример DNS сервера с libvirt

Этот пример создаёт DNS сервер на базе PowerDNS локально используя libvirt/KVM.

## 🚀 Quick Start

Для быстрого старта см. [QUICKSTART.md](QUICKSTART.md) - упрощённое руководство с пошаговыми инструкциями.

**Helpful scripts:**
- `check-vm-status.sh` - Проверка статуса VM и автоматическая диагностика (запускается на хосте)
- `diagnose-and-fix.sh` - Диагностика и исправление проблем PowerDNS (запускается на VM)
- `test-dns-server.sh` - Полное тестирование DNS сервера (запускается на хосте)

### Типичный workflow:

```bash
# 1. Применить terraform
terraform init
terraform apply

# 2. Подождать 3-5 минут для provisioning

# 3. Проверить статус VM
./check-vm-status.sh

# 4. Если есть проблемы, скрипт автоматически запустит диагностику

# 5. Запустить тесты
./test-dns-server.sh
```

## Предварительные требования

**Автоматическая проверка:** Перед началом запустите скрипт проверки всех зависимостей:
```bash
cd ../.. # Перейти в корень репозитория
./scripts/check-prerequisites.sh
```

1. Установленный libvirt и KVM:
```bash
# Ubuntu/Debian
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils xsltproc

# Fedora/RHEL
sudo dnf install -y qemu-kvm libvirt virt-install libxslt

# Включение и запуск libvirt
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Добавление пользователя в группу libvirt
sudo usermod -a -G libvirt $(whoami)
newgrp libvirt
```

2. Установленный Terraform:
```bash
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

3. SSH ключ:
```bash
# Если у вас нет SSH ключа, создайте его
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

4. (Опционально) Настройка переменных:
```bash
# Скопируйте пример файла с переменными
cp terraform.tfvars.example terraform.tfvars

# Отредактируйте terraform.tfvars и укажите путь к вашему SSH ключу
# или вставьте содержимое SSH ключа напрямую
```

**Примечание:** Если ваш SSH ключ находится не в стандартном месте (`~/.ssh/id_rsa.pub`),
вы можете настроить путь через переменную `ssh_public_key_path` в файле `terraform.tfvars`.

## Использование

### ⚠️ Важно: Настройка окружения при работе через прокси

Если вы работаете в окружении с прокси-сервером, перед запуском `terraform init` необходимо настроить переменную окружения `NO_PROXY`:

```bash
# Вариант 1: Использовать скрипт автоматической настройки (рекомендуется)
cd examples/local
source ../../scripts/setup-terraform-env.sh

# Вариант 2: Настроить вручную
export NO_PROXY="${NO_PROXY},registry.terraform.io,releases.hashicorp.com"

# Вариант 3: Временно отключить прокси
unset HTTP_PROXY HTTPS_PROXY
```

После настройки окружения можно приступать к работе с Terraform.

1. Инициализация Terraform:
```bash
cd examples/local
terraform init
```

2. Просмотр плана:
```bash
terraform plan
```

3. Применение конфигурации:
```bash
terraform apply
```

4. После успешного применения вы получите информацию о сервере:
```bash
# Посмотреть все outputs
terraform output

# Получить TSIG секрет
terraform output -raw tsig_secret

# Получить пример использования nsupdate
terraform output -raw nsupdate_example
```

## Проверка работы DNS сервера

1. Проверить IP адрес VM:
```bash
virsh domifaddr dns-server
```

2. Подключиться к серверу:
```bash
# SSH
ssh root@192.168.200.100

# Или через virsh console
virsh console dns-server
```

3. Проверить статус PowerDNS:
```bash
systemctl status pdns
```

4. Проверить DNS зону:
```bash
dig @192.168.200.100 test.local SOA
dig @192.168.200.100 test.local NS
```

5. Проверить firewall:
```bash
sudo ufw status
```

## Тестирование динамического DNS (RFC-2136)

1. Получить TSIG секрет:
```bash
TSIG_SECRET=$(terraform output -raw tsig_secret)
echo $TSIG_SECRET
```

2. Создать файл с TSIG ключом:
```bash
cat > /tmp/tsig.key <<EOF
key "txt-updater" {
  algorithm hmac-sha256;
  secret "$TSIG_SECRET";
};
EOF
```

3. Добавить TXT запись:
```bash
nsupdate -k /tmp/tsig.key <<EOF
server 192.168.200.100
zone test.local
update add _acme-challenge.test.local. 300 IN TXT "test-txt-record-123"
send
EOF
```

4. Проверить запись:
```bash
dig @192.168.200.100 _acme-challenge.test.local TXT
```

5. Удалить запись:
```bash
nsupdate -k /tmp/tsig.key <<EOF
server 192.168.200.100
zone test.local
update delete _acme-challenge.test.local. TXT
send
EOF
```

## Использование PowerDNS API

1. Получить API ключ:
```bash
PDNS_API_KEY=$(terraform output -raw pdns_api_key)
```

2. Просмотр зон:
```bash
curl -s -H "X-API-Key: $PDNS_API_KEY" \
  http://192.168.200.100:8081/api/v1/servers/localhost/zones | jq
```

3. Просмотр записей зоны:
```bash
curl -s -H "X-API-Key: $PDNS_API_KEY" \
  http://192.168.200.100:8081/api/v1/servers/localhost/zones/test.local | jq
```

## Настройка WireGuard (опционально)

Если вам нужно подключить DNS сервер к WireGuard туннелю:

1. Сгенерировать ключи WireGuard:
```bash
wg genkey | tee privatekey | wg pubkey > publickey
```

2. Обновить `main.tf`:
```hcl
wg_config = {
  enabled          = true
  private_key      = file("privatekey")
  address          = "10.0.0.2/24"
  peer_public_key  = "PEER_PUBLIC_KEY"
  peer_endpoint    = "vpn.example.com:51820"
  peer_allowed_ips = ["10.0.0.0/24"]
}
```

3. Применить изменения:
```bash
terraform apply
```

## Очистка

Удалить все созданные ресурсы:
```bash
terraform destroy
```

## Troubleshooting

### ⚠️ Ошибка "Permission denied" при создании VM

Если при создании libvirt domain вы получаете ошибку:
```
Error: error creating libvirt domain: internal error: process exited while connecting to monitor:
qemu-system-x86_64: -blockdev {...}: Could not open '/var/lib/libvirt/pools/dns-server/dns-server-base.qcow2': Permission denied
```

**Самая частая причина:** Не установлен пакет `xsltproc`.

**Решение:**
```bash
# Ubuntu/Debian
apt-get install -y xsltproc

# Fedora/RHEL
dnf install -y libxslt

# После установки повторите terraform apply
terraform apply
```

Подробности см. в [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md)

### Ошибка "xsltproc: executable file not found in $PATH"

Если при создании libvirt domain вы получаете ошибку:
```
Error: error applying XSLT stylesheet: exec: "xsltproc": executable file not found in $PATH
  with module.dns_server.libvirt_domain.dns_server
```

**Причина:** Отсутствует утилита `xsltproc`, необходимая для работы libvirt провайдера Terraform.

**Решение:**
```bash
# Ubuntu/Debian
apt-get install -y xsltproc

# Fedora/RHEL
dnf install -y libxslt
```

### Ошибка "can't find storage pool 'default'"

Если при запуске `terraform apply` вы получаете ошибку:
```
Error: can't find storage pool 'default'
  with module.dns_server.libvirt_volume.base
```

**Причина:** Storage pool 'default' не создан в вашей системе libvirt.

**Решение:** Terraform автоматически создаст storage pool. Если вы хотите использовать другой путь для хранения образов, укажите переменную `pool_path` в `terraform.tfvars`:
```hcl
pool_path = "/custom/path/to/images"
```

По умолчанию используется `/var/lib/libvirt/images`. Убедитесь, что у пользователя есть права на запись в эту директорию:
```bash
sudo mkdir -p /var/lib/libvirt/images
sudo chown root:libvirt /var/lib/libvirt/images
sudo chmod 775 /var/lib/libvirt/images
```

### Ошибка "Network is already in use by interface virbr0"

Если при запуске `terraform apply` вы получаете ошибку:
```
Error: error creating libvirt network: internal error: Network is already in use by interface virbr0
  with module.dns_server.libvirt_network.dns_network
```

**Причина:** Диапазон IP 192.168.122.0/24 уже используется существующей сетью libvirt (virbr0).

**Решение:** Конфигурация по умолчанию изменена на 192.168.200.0/24. Если вы все еще получаете эту ошибку, выберите другой диапазон сети в `terraform.tfvars`:
```hcl
network_cidr  = "192.168.201.0/24"
dns_server_ip = "192.168.201.100"
```

Или удалите существующую сеть (если она не используется):
```bash
virsh net-destroy default
virsh net-undefine default
```

### Ошибка "Invalid function argument" - SSH ключ не найден

Если при запуске `terraform apply` вы получаете ошибку:
```
Error: Invalid function argument
on main.tf line 21, in module "dns_server":
  21:   ssh_public_key = file(pathexpand("~/.ssh/id_rsa.pub"))
Invalid value for "path" parameter: no file exists at "/home/user/.ssh/id_rsa.pub"
```

**Причина:** SSH ключ не найден по указанному пути.

**Решение:**

1. Создайте SSH ключ:
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

2. Или укажите другой путь к существующему ключу в `terraform.tfvars`:
```hcl
ssh_public_key_path = "~/.ssh/my_custom_key.pub"
```

3. Или вставьте содержимое SSH ключа напрямую в `terraform.tfvars`:
```hcl
ssh_public_key_content = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... your-email@example.com"
```

### Ошибка "Invalid provider registry host"

Если при запуске `terraform init` вы получаете ошибку:
```
Error: Invalid provider registry host
The host "registry.terraform.io" given in provider source address
does not offer a Terraform provider registry.
```

**Причина:** Ваше окружение использует прокси-сервер, и `registry.terraform.io` не добавлен в список исключений `NO_PROXY`.

**Решение:**
```bash
# Способ 1: Использовать скрипт (рекомендуется)
source ../../scripts/setup-terraform-env.sh
terraform init

# Способ 2: Добавить вручную в NO_PROXY
export NO_PROXY="${NO_PROXY},registry.terraform.io,releases.hashicorp.com"
terraform init

# Способ 3: Временно отключить прокси
unset HTTP_PROXY HTTPS_PROXY
terraform init
```

Для постоянного решения добавьте в `~/.bashrc` или `~/.zshrc`:
```bash
export NO_PROXY="${NO_PROXY},registry.terraform.io,releases.hashicorp.com"
```

### VM не запускается

Проверить логи:
```bash
virsh console dns-server
# или
tail -f /var/log/libvirt/qemu/dns-server.log
```

### Cloud-init не отработал

Проверить логи cloud-init:
```bash
ssh root@192.168.200.100
tail -f /var/log/cloud-init-output.log
```

### PowerDNS не отвечает

Проверить статус и логи:
```bash
systemctl status pdns
journalctl -u pdns -f
```

### TSIG аутентификация не работает

Проверить TSIG ключ в базе данных:
```bash
sqlite3 /var/lib/powerdns/pdns.sqlite3 "SELECT * FROM tsigkeys;"
```

## Дополнительные команды

Список всех VM:
```bash
virsh list --all
```

Информация о VM:
```bash
virsh dominfo dns-server
```

Остановка VM:
```bash
virsh shutdown dns-server
```

Удаление VM:
```bash
virsh destroy dns-server
virsh undefine dns-server
```
