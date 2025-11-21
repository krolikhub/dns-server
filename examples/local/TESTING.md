# Проверка DNS сервера

## Автоматическая проверка

Запустите скрипт автоматической проверки:

```bash
./test-dns-server.sh
```

Скрипт проверит:
- ✓ Доступность сервера (ping)
- ✓ SSH доступ
- ✓ DNS работу (SOA и NS записи)
- ✓ PowerDNS API
- ✓ Динамическое обновление через nsupdate (TSIG)

---

## Ручная проверка

### 1. Проверка доступности

```bash
ping -c 3 192.168.200.100
```

Ожидаемый результат: сервер отвечает на ping

---

### 2. Проверка SSH доступа

```bash
ssh -o StrictHostKeyChecking=no root@192.168.200.100
```

Ожидаемый результат: успешное подключение без пароля

**Внутри VM проверьте сервисы:**

```bash
# Статус PowerDNS
systemctl status pdns

# Логи PowerDNS
journalctl -u pdns -n 50

# Проверка портов
ss -tulpn | grep -E ':(53|8081)'
```

---

### 3. Проверка DNS запросов

**SOA запись:**
```bash
dig @192.168.200.100 test.local SOA
```

Ожидаемый результат:
```
;; ANSWER SECTION:
test.local.		3600	IN	SOA	ns1.test.local. hostmaster.test.local. ...
```

**NS запись:**
```bash
dig @192.168.200.100 test.local NS
```

Ожидаемый результат:
```
;; ANSWER SECTION:
test.local.		3600	IN	NS	ns1.test.local.
```

**A запись для NS:**
```bash
dig @192.168.200.100 ns1.test.local A
```

Ожидаемый результат:
```
;; ANSWER SECTION:
ns1.test.local.		3600	IN	A	192.168.200.100
```

---

### 4. Проверка PowerDNS API

```bash
# Получить список зон
curl -s http://192.168.200.100:8081/api/v1/servers/localhost/zones | jq '.'

# Получить информацию о конкретной зоне
curl -s http://192.168.200.100:8081/api/v1/servers/localhost/zones/test.local | jq '.'
```

Ожидаемый результат: JSON с информацией о зоне

---

### 5. Проверка динамического обновления (nsupdate + TSIG)

**Создать файл с TSIG ключом:**

```bash
# Получить секрет из Terraform
TSIG_SECRET=$(terraform output -raw tsig_secret)

# Создать файл с ключом
cat > /tmp/tsig.key <<EOF
key "txt-updater" {
  algorithm hmac-sha256;
  secret "$TSIG_SECRET";
};
EOF
```

**Добавить TXT запись:**

```bash
nsupdate -k /tmp/tsig.key <<EOF
server 192.168.200.100
zone test.local
update add _acme-challenge.test.local. 300 IN TXT "my-test-value-123"
send
EOF
```

**Проверить добавленную запись:**

```bash
dig @192.168.200.100 _acme-challenge.test.local TXT +short
```

Ожидаемый результат:
```
"my-test-value-123"
```

**Удалить тестовую запись:**

```bash
nsupdate -k /tmp/tsig.key <<EOF
server 192.168.200.100
zone test.local
update delete _acme-challenge.test.local. TXT
send
EOF
```

**Проверить, что запись удалена:**

```bash
dig @192.168.200.100 _acme-challenge.test.local TXT
```

Ожидаемый результат: пустой ANSWER SECTION

---

## Отладка проблем

### SSH подключение не работает (Permission denied)

Эта проблема возникает, когда SSH клиент пытается использовать не тот ключ, который был установлен на VM при создании.

**Симптомы:**
- SSH возвращает `Permission denied (publickey)`
- Консоль virsh требует пароль (вход без пароля не работает)
- Любые SSH ключи не подходят

**Причина:**
Cloud-init не установил SSH ключ, потому что Terraform передал несуществующий ключ (по умолчанию `~/.ssh/id_rsa.pub`, которого может не быть).

**Диагностика:**

1. **Проверьте, какой ключ был использован при создании VM:**
```bash
# Посмотрите в terraform.tfvars (если файл существует)
cat terraform.tfvars

# Или проверьте значение по умолчанию в variables.tf
cat variables.tf
# По умолчанию используется: ~/.ssh/id_rsa.pub
```

2. **Проверьте, какой ключ установлен на VM через консоль:**
```bash
# Подключитесь к консоли VM
sudo virsh console dns-server

# После входа (логин: root, может потребоваться нажать Enter)
cat /root/.ssh/authorized_keys

# Для выхода из консоли: Ctrl+]
```

3. **Сравните с вашими локальными ключами:**
```bash
# Посмотрите все ваши публичные ключи
ls -la ~/.ssh/*.pub

# Просмотрите содержимое
cat ~/.ssh/id_rsa.pub
cat ~/.ssh/id_ed25519.pub
```

**Решение 1: Используйте правильный ключ**

Если ключ `id_rsa.pub` был установлен на VM, используйте соответствующий приватный ключ:
```bash
ssh -i ~/.ssh/id_rsa root@192.168.200.100
```

Или настройте SSH config для постоянного использования:
```bash
cat >> ~/.ssh/config <<'EOF'
Host 192.168.200.100
    IdentityFile ~/.ssh/id_rsa
    User root
    StrictHostKeyChecking no
EOF
```

**Решение 2: Пересоздайте VM с нужным ключом**

Если вы хотите использовать другой ключ (например, `id_ed25519`):

1. Создайте `terraform.tfvars`:
```bash
cat > terraform.tfvars <<'EOF'
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
EOF
```

2. Пересоздайте VM:
```bash
terraform destroy -auto-approve
terraform apply -auto-approve
```

**Решение 3: Добавьте дополнительный ключ на существующую VM**

Если не хотите пересоздавать VM:
```bash
# Через консоль virsh
sudo virsh console dns-server

# После входа добавьте новый ключ
echo "ваш-новый-публичный-ключ" >> /root/.ssh/authorized_keys
```

---

### DNS не отвечает

```bash
# Проверить, запущен ли PowerDNS
ssh root@192.168.200.100 "systemctl status pdns"

# Проверить логи
ssh root@192.168.200.100 "journalctl -u pdns -n 100"

# Проверить, слушает ли порт 53
ssh root@192.168.200.100 "ss -tulpn | grep :53"
```

### nsupdate не работает

```bash
# Проверить конфигурацию TSIG на сервере
ssh root@192.168.200.100 "cat /etc/powerdns/pdns.conf | grep -A 5 dnsupdate"

# Попробовать с отладкой
nsupdate -d -k /tmp/tsig.key <<EOF
server 192.168.200.100
zone test.local
update add test.test.local. 60 IN A 1.2.3.4
send
EOF
```

### API не отвечает

```bash
# Проверить, запущен ли веб-сервер API
ssh root@192.168.200.100 "ss -tulpn | grep :8081"

# Проверить конфигурацию API
ssh root@192.168.200.100 "cat /etc/powerdns/pdns.conf | grep api"
```

---

## Дополнительные команды

```bash
# Подключиться к консоли VM через virsh
virsh console dns-server

# Перезапустить PowerDNS
ssh root@192.168.200.100 "systemctl restart pdns"

# Посмотреть все записи зоны
ssh root@192.168.200.100 "pdnsutil list-zone test.local"

# Экспорт зоны в текстовом формате
ssh root@192.168.200.100 "pdnsutil export-zone test.local"
```

---

## Что означает вывод Terraform

```
Apply complete! Resources: 5 added, 1 changed, 0 destroyed.
```

**Созданные ресурсы:**
- Виртуальная машина (libvirt_domain)
- Диск виртуальной машины (libvirt_volume)
- Виртуальная сеть (libvirt_network)
- Cloud-init конфигурация (libvirt_cloudinit_disk)
- TSIG ключ для безопасных обновлений (random_password)

**Outputs:**
- `dns_server_ip` - IP адрес DNS сервера
- `dns_zone` - имя DNS зоны
- `tsig_key_name` - имя TSIG ключа
- `tsig_secret` - секрет TSIG ключа (помечен как sensitive)
- `pdns_api_url` - URL для доступа к PowerDNS API
- `ssh_command` - команда для SSH подключения
- `test_dns_command` - команда для проверки DNS
- `nsupdate_example` - пример использования nsupdate
