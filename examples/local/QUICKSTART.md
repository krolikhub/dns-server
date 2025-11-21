# Quick Start Guide

Это быстрое руководство поможет вам запустить DNS сервер за несколько минут.

## Предварительная проверка

### 1. Проверьте зависимости

```bash
# Перейдите в корень репозитория и запустите скрипт проверки
cd ../..
./scripts/check-prerequisites.sh
```

### 2. Проверьте SSH ключи

**⚠️ ВАЖНО:** По умолчанию используется ключ `~/.ssh/id_rsa.pub`. Если у вас его нет или вы хотите использовать другой ключ, настройте это перед созданием VM!

```bash
# Проверьте, какие SSH ключи у вас есть
ls -la ~/.ssh/*.pub

# Если нет id_rsa.pub, создайте его ИЛИ настройте другой ключ
```

**Вариант А: Создать ключ id_rsa**
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

**Вариант Б: Использовать существующий ключ (например, id_ed25519)**
```bash
# Создайте файл terraform.tfvars
cat > examples/local/terraform.tfvars <<'EOF'
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
EOF
```

## Быстрый старт

### 1. Перейдите в директорию с примером

```bash
cd examples/local
```

### 2. Инициализируйте Terraform

```bash
terraform init
```

### 3. Примените конфигурацию

```bash
terraform apply -auto-approve
```

Подождите ~2-3 минуты пока VM создастся и настроится.

### 4. Проверьте работу

```bash
# Автоматическая проверка
./test-dns-server.sh

# Или проверьте вручную
terraform output ssh_command
# Выполните показанную команду для подключения по SSH
```

## Быстрая диагностика SSH проблем

Если SSH не работает (`Permission denied`):

### Шаг 1: Узнайте, какой ключ используется

```bash
# Посмотрите в terraform.tfvars (если файл существует)
cat terraform.tfvars

# Если файла нет, по умолчанию используется ~/.ssh/id_rsa.pub
```

### Шаг 2: Попробуйте подключиться с явным указанием ключа

```bash
# Если использовался id_rsa.pub
ssh -i ~/.ssh/id_rsa root@192.168.200.100

# Если использовался id_ed25519.pub
ssh -i ~/.ssh/id_ed25519 root@192.168.200.100
```

### Шаг 3: Если не помогло - проверьте через консоль

```bash
# Подключитесь к консоли VM
sudo virsh console dns-server

# Нажмите Enter несколько раз, затем войдите как root (без пароля)
# Проверьте установленный ключ:
cat /root/.ssh/authorized_keys

# Сравните с вашими локальными ключами:
# (в другом терминале)
cat ~/.ssh/id_rsa.pub
cat ~/.ssh/id_ed25519.pub

# Для выхода из консоли: Ctrl+]
```

### Шаг 4: Решение

**Если нашли правильный ключ:**
```bash
# Используйте его для подключения
ssh -i ~/.ssh/ваш_ключ root@192.168.200.100

# Или настройте SSH config
cat >> ~/.ssh/config <<'EOF'
Host 192.168.200.100
    IdentityFile ~/.ssh/ваш_ключ
    User root
    StrictHostKeyChecking no
EOF
```

**Если хотите использовать другой ключ:**
```bash
# 1. Создайте terraform.tfvars с нужным ключом
cat > terraform.tfvars <<'EOF'
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
EOF

# 2. Пересоздайте VM
terraform destroy -auto-approve
terraform apply -auto-approve
```

## Что дальше?

После успешного подключения:

1. **Проверьте DNS:**
```bash
dig @192.168.200.100 test.local SOA
```

2. **Проверьте PowerDNS API:**
```bash
curl -s http://192.168.200.100:8081/api/v1/servers/localhost/zones | jq '.'
```

3. **Протестируйте динамическое обновление:**
```bash
# Получите TSIG секрет
TSIG_SECRET=$(terraform output -raw tsig_secret)

# Создайте файл с ключом
cat > /tmp/tsig.key <<EOF
key "txt-updater" {
  algorithm hmac-sha256;
  secret "$TSIG_SECRET";
};
EOF

# Добавьте тестовую запись
nsupdate -k /tmp/tsig.key <<EOF
server 192.168.200.100
zone test.local
update add test-record.test.local. 300 IN A 10.0.0.1
send
EOF

# Проверьте
dig @192.168.200.100 test-record.test.local A +short
```

## Полная документация

- [README.md](README.md) - Полное описание примера
- [TESTING.md](TESTING.md) - Подробное руководство по тестированию и отладке

## Частые проблемы

| Проблема | Решение |
|----------|---------|
| SSH: Permission denied | См. "Быстрая диагностика SSH проблем" выше |
| DNS не отвечает | Подождите 2-3 минуты после apply, проверьте `ssh root@192.168.200.100 'systemctl status pdns'` |
| Terraform init не работает за прокси | Запустите `source ../../scripts/setup-terraform-env.sh` |
| VM не создается | Проверьте права libvirt: `sudo usermod -a -G libvirt $(whoami) && newgrp libvirt` |

## Удаление

Когда закончите работу:

```bash
terraform destroy -auto-approve
```

Это удалит VM, диск и виртуальную сеть.
