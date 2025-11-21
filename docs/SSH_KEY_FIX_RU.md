# Исправление проблемы с SSH ключами

## Описание проблемы

После запуска debug скрипта `bash scripts/debug-ssh-full.sh` обнаружена проблема:

```
debug1: Offering public key: /home/cogito/.ssh/id_rsa RSA SHA256:PILFSggaLUvOEbRhl/lHB6hlwq+JUJ8cm6NwgVGvxNA agent
debug3: receive packet: type 51
debug1: Authentications that can continue: publickey
```

**Проблема**: SSH клиент предлагает правильный ключ, но сервер его отвергает.

### Причины проблемы

1. **Cloud-init не добавил ключ в authorized_keys** - по какой-то причине процесс инициализации VM не записал SSH ключ в файл `/home/ubuntu/.ssh/authorized_keys`

2. **Неправильные права доступа** - даже если ключ добавлен, SSH сервер может отвергать его из-за слишком открытых прав доступа к файлам:
   - `~/.ssh/` должна иметь права `700` (drwx------)
   - `~/.ssh/authorized_keys` должен иметь права `600` (-rw-------)

3. **Ключ был добавлен неправильно** - возможно есть проблемы с форматом или переносами строк

## Решение

### Вариант 1: Автоматическое исправление (РЕКОМЕНДУЕТСЯ)

Используйте скрипт `fix-ssh-keys.sh`:

```bash
bash scripts/fix-ssh-keys.sh
```

Скрипт:
1. Подключится к VM по паролю (пароль по умолчанию: `ubuntu`)
2. Создаст директорию `.ssh` если не существует
3. Добавит ваш публичный ключ в `authorized_keys`
4. Установит правильные права доступа
5. Проверит результат

**Параметры** (опционально):
```bash
bash scripts/fix-ssh-keys.sh [VM_IP] [USER] [PASSWORD] [PUBLIC_KEY_PATH]
```

Например:
```bash
bash scripts/fix-ssh-keys.sh 192.168.200.100 ubuntu ubuntu ~/.ssh/id_rsa.pub
```

### Вариант 2: Ручное исправление через virsh console

Если парольная аутентификация не работает, используйте консоль VM:

```bash
sudo virsh console dns-server
# Логин: ubuntu
# Пароль: ubuntu
```

Затем выполните команды:

```bash
# Создать директорию если не существует
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Добавить публичный ключ
cat >> ~/.ssh/authorized_keys << 'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDOI7bee9bRpyU8sry+k6Wjctz+yT+gHt3f6B1Gdb3rjNc10icgWOLmUe8/JPWgq8GSm9TTlV6ocKvfVCvoBYdu7LEiDOATruwUy4EkUmGmU9HER0DKGwWf60EZ8C/V1Fpe67KonkWWAEBJzDkRnvjqLZMROq6meB0GAfyx/Qcqpqq3rRCYbPNVqryFTOoZKwwJFaK1Cmi9qu4FUca1LlD6FT71XCexvDif7rBMFLlKzdaJVf6S24GQAfnLeyazTnk3XYiMWq945CCb2UpNSSbPEssZ9mk3gTbdfLkhcJPU+WIAR17Kp89HITn3tCvRuxzXS2wKZDtXr+Vg10a6PB6ekD7ZhdOJDCs0U18pZyay2XzGAy6GDI31fMi8+kzr5Dad4w4ar//0KcbFM42YLo5vtqvPRzU8dFv0qgr/R3pk/TI6EV1EYbrN8lWqQGhjwU+9Aa4x5cAABEe0FE3M+uQurD6I19AfBhOIvGS7xoDGwruLcRpiaeaM4XD9f4mKMGiqeO01K1H07Ea1UR9RvtnToiSMOaKJ95mlJVRJXzfyV4EjXItiZGHifYVyDlrDqL1FbJ/C/dl2pnJycEFo//duogWNNfSgkUcQ2kFGZ/h24OBxHCwC0MiJtext82eYgAYf1jjbakeQpRaIRRwz5TfazXtowqVEOczqvQ/2f4W/7w== cogito@Tokens
EOF

# Установить правильные права
chmod 600 ~/.ssh/authorized_keys

# Убедиться что владелец правильный
chown -R ubuntu:ubuntu ~/.ssh

# Проверить результат
ls -la ~/.ssh/
cat ~/.ssh/authorized_keys

# Выйти из консоли (Ctrl+])
```

### Вариант 3: Пересоздание VM

Если исправления не помогают, можно пересоздать VM:

```bash
cd examples/local
bash ../../scripts/recreate-vm.sh
```

Это удалит текущую VM и создаст новую с правильной конфигурацией.

## Проверка результата

После исправления проверьте подключение:

```bash
# Простое подключение
ssh ubuntu@192.168.200.100

# Или с указанием ключа
ssh -i ~/.ssh/id_rsa ubuntu@192.168.200.100
```

Если все работает, вы должны подключиться БЕЗ запроса пароля.

## Диагностика если проблема остается

### 1. Проверить что ключ правильный

На локальной машине:
```bash
cat ~/.ssh/id_rsa.pub
```

На VM:
```bash
ssh -o PreferredAuthentications=password ubuntu@192.168.200.100 'cat ~/.ssh/authorized_keys'
```

Содержимое должно совпадать.

### 2. Проверить права доступа

На VM:
```bash
ssh -o PreferredAuthentications=password ubuntu@192.168.200.100 'ls -la ~/.ssh/'
```

Ожидаемый результат:
```
drwx------ 2 ubuntu ubuntu 4096 ... .
-rw------- 1 ubuntu ubuntu  xxx ... authorized_keys
```

### 3. Проверить SSH конфигурацию сервера

На VM:
```bash
ssh -o PreferredAuthentications=password ubuntu@192.168.200.100 'sudo sshd -T | grep -E "(pubkeyauth|authorizedkeys)"'
```

Должно быть:
```
pubkeyauthentication yes
authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2
```

### 4. Проверить логи SSH на VM

```bash
ssh -o PreferredAuthentications=password ubuntu@192.168.200.100 'sudo tail -50 /var/log/auth.log'
```

Ищите строки типа:
```
sshd[xxx]: Authentication refused: bad ownership or modes for directory /home/ubuntu/.ssh
```

## Понимание проблемы

### Как работает SSH аутентификация по ключу

1. **Клиент** предлагает публичный ключ серверу
2. **Сервер** проверяет:
   - Есть ли этот ключ в `/home/ubuntu/.ssh/authorized_keys`
   - Правильные ли права доступа к файлам
   - Разрешена ли аутентификация по ключам в конфигурации
3. Если все проверки пройдены, сервер отправляет challenge
4. Клиент подписывает challenge приватным ключом
5. Сервер проверяет подпись публичным ключом
6. Если подпись правильная - доступ разрешен

### Почему строгие права доступа важны

SSH сервер требует строгие права доступа для безопасности:
- Если другие пользователи могут записывать в `~/.ssh/` или `~/.ssh/authorized_keys`, они могут добавить свои ключи
- Поэтому SSH отвергает ключи если права доступа слишком открытые
- Требуемые права: `700` для директории, `600` для файлов

### Что делает cloud-init при создании VM

В `cloud-init/user-data.yml` определено:
```yaml
users:
  - name: ubuntu
    ssh_authorized_keys:
      - ${ssh_public_key}
```

При создании VM через Terraform:
1. Terraform читает публичный ключ из `~/.ssh/id_rsa.pub`
2. Подставляет содержимое в `${ssh_public_key}`
3. Cloud-init должен создать файл `/home/ubuntu/.ssh/authorized_keys` с этим ключом
4. Cloud-init должен установить правильные права доступа

Если что-то пошло не так на любом из этих этапов - аутентификация по ключу не работает.

## Превентивные меры

Чтобы избежать проблемы в будущем:

### 1. Проверка перед созданием VM

Убедитесь что публичный ключ существует:
```bash
ls -la ~/.ssh/id_rsa.pub
```

Если нет - создайте:
```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

### 2. Проверка после создания VM

Сразу после `terraform apply` проверьте:
```bash
bash scripts/debug-ssh-full.sh
```

### 3. Мониторинг cloud-init

Проверьте что cloud-init завершился успешно:
```bash
ssh -o PreferredAuthentications=password ubuntu@192.168.200.100 'cloud-init status'
```

Должно быть: `status: done`

Если `status: running` - подождите завершения:
```bash
ssh -o PreferredAuthentications=password ubuntu@192.168.200.100 'cloud-init status --wait'
```

## Полезные команды

```bash
# Проверка статуса VM
virsh list --all

# Подключение к консоли VM
sudo virsh console dns-server

# Перезапуск VM
virsh reboot dns-server

# Остановка VM
virsh shutdown dns-server

# Запуск VM
virsh start dns-server

# Удаление VM
virsh destroy dns-server
virsh undefine dns-server

# Просмотр логов cloud-init на VM
ssh -o PreferredAuthentications=password ubuntu@192.168.200.100 'sudo cat /var/log/cloud-init-output.log'

# Проверка SSH ключей в агенте
ssh-add -l

# Очистка SSH known_hosts
ssh-keygen -R 192.168.200.100
```

## Дополнительная информация

- [SSH Key Authentication](https://www.ssh.com/academy/ssh/public-key-authentication)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Libvirt Documentation](https://libvirt.org/docs.html)
