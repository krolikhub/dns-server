# Локальный пример DNS сервера с libvirt

Этот пример создаёт DNS сервер на базе PowerDNS локально используя libvirt/KVM.

## Предварительные требования

1. Установленный libvirt и KVM:
```bash
# Ubuntu/Debian
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

# Fedora/RHEL
sudo dnf install -y qemu-kvm libvirt virt-install

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
# Если у вас нет SSH ключа
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

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
ssh root@192.168.122.100

# Или через virsh console
virsh console dns-server
```

3. Проверить статус PowerDNS:
```bash
systemctl status pdns
```

4. Проверить DNS зону:
```bash
dig @192.168.122.100 test.local SOA
dig @192.168.122.100 test.local NS
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
server 192.168.122.100
zone test.local
update add _acme-challenge.test.local. 300 IN TXT "test-txt-record-123"
send
EOF
```

4. Проверить запись:
```bash
dig @192.168.122.100 _acme-challenge.test.local TXT
```

5. Удалить запись:
```bash
nsupdate -k /tmp/tsig.key <<EOF
server 192.168.122.100
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
  http://192.168.122.100:8081/api/v1/servers/localhost/zones | jq
```

3. Просмотр записей зоны:
```bash
curl -s -H "X-API-Key: $PDNS_API_KEY" \
  http://192.168.122.100:8081/api/v1/servers/localhost/zones/test.local | jq
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
ssh root@192.168.122.100
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
