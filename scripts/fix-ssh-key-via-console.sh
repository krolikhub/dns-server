#!/bin/bash
#
# Скрипт для добавления SSH ключа через virsh console
# Используется когда текущий SSH ключ не работает
#

set -e

VM_NAME="dns-server"
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║              ИСПРАВЛЕНИЕ SSH КЛЮЧА ЧЕРЕЗ VIRSH CONSOLE                       ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Проверка наличия публичного ключа
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "✗ SSH ключ не найден: $SSH_KEY_PATH"
    echo ""
    echo "Доступные SSH ключи:"
    ls -la ~/.ssh/*.pub 2>/dev/null || echo "  Нет публичных ключей"
    exit 1
fi

echo "✓ SSH ключ найден: $SSH_KEY_PATH"
echo ""

# Читаем публичный ключ
SSH_PUB_KEY=$(cat "$SSH_KEY_PATH")
echo "Публичный ключ:"
echo "  ${SSH_PUB_KEY:0:60}..."
echo ""

# Проверка существования VM
if ! sudo virsh list --all | grep -q "$VM_NAME"; then
    echo "✗ VM '$VM_NAME' не найдена"
    exit 1
fi

echo "✓ VM '$VM_NAME' найдена"
echo ""

# Проверка запущена ли VM
VM_STATE=$(sudo virsh domstate "$VM_NAME")
if [ "$VM_STATE" != "running" ]; then
    echo "✗ VM не запущена (состояние: $VM_STATE)"
    echo "  Запустите VM: sudo virsh start $VM_NAME"
    exit 1
fi

echo "✓ VM запущена"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                     ИНСТРУКЦИИ ДЛЯ РУЧНОГО ИСПРАВЛЕНИЯ                       ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Для добавления SSH ключа нужно:"
echo ""
echo "1. Подключиться к консоли VM:"
echo "   sudo virsh console $VM_NAME"
echo ""
echo "2. Войти с логином 'ubuntu' и паролем 'ubuntu'"
echo ""
echo "3. Выполнить следующие команды:"
echo ""
echo "   mkdir -p ~/.ssh"
echo "   chmod 700 ~/.ssh"
echo "   echo '$SSH_PUB_KEY' >> ~/.ssh/authorized_keys"
echo "   chmod 600 ~/.ssh/authorized_keys"
echo ""
echo "4. Выйти из консоли (Ctrl+])"
echo ""
echo "5. Проверить подключение:"
echo "   ssh -i ${SSH_KEY_PATH%.pub} ubuntu@192.168.200.100"
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                     АВТОМАТИЧЕСКОЕ ИСПРАВЛЕНИЕ                               ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Пробуем добавить ключ автоматически через expect..."
echo ""

# Проверка наличия expect
if ! command -v expect &> /dev/null; then
    echo "⚠  expect не установлен"
    echo "   Установите: sudo apt-get install expect"
    echo ""
    echo "Или добавьте ключ вручную (см. инструкции выше)"
    exit 0
fi

# Создаем временный expect скрипт
EXPECT_SCRIPT=$(mktemp)
cat > "$EXPECT_SCRIPT" <<'EOF'
#!/usr/bin/expect -f

set timeout 30
set vm_name [lindex $argv 0]
set ssh_key [lindex $argv 1]

# Подключаемся к консоли
spawn sudo virsh console $vm_name

# Ждем приглашение логина (может уже быть залогинен)
expect {
    "login:" {
        send "ubuntu\r"
        expect "Password:"
        send "ubuntu\r"
    }
    "ubuntu@" {
        # Уже залогинен
    }
    timeout {
        puts "\n✗ Timeout waiting for login prompt"
        exit 1
    }
}

# Ждем приглашение командной строки
expect "ubuntu@"

# Создаем директорию .ssh
send "mkdir -p ~/.ssh && chmod 700 ~/.ssh\r"
expect "ubuntu@"

# Добавляем ключ
send "echo '$ssh_key' >> ~/.ssh/authorized_keys\r"
expect "ubuntu@"

# Устанавливаем права
send "chmod 600 ~/.ssh/authorized_keys\r"
expect "ubuntu@"

# Проверяем что ключ добавлен
send "tail -n1 ~/.ssh/authorized_keys\r"
expect "ubuntu@"

# Выходим из консоли
send "\x1d"
expect eof

puts "\n✓ SSH ключ успешно добавлен!"
EOF

chmod +x "$EXPECT_SCRIPT"

# Запускаем expect скрипт
if "$EXPECT_SCRIPT" "$VM_NAME" "$SSH_PUB_KEY"; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           ПРОВЕРКА ПОДКЛЮЧЕНИЯ                               ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Проверяем SSH подключение..."
    sleep 2

    if ssh -i "${SSH_KEY_PATH%.pub}" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@192.168.200.100 "echo 'SSH works!'" 2>/dev/null; then
        echo "✓ SSH подключение работает!"
        echo ""
        echo "Команда для подключения:"
        echo "  ssh ubuntu@192.168.200.100"
    else
        echo "✗ SSH подключение не работает"
        echo ""
        echo "Попробуйте вручную:"
        echo "  ssh -i ${SSH_KEY_PATH%.pub} ubuntu@192.168.200.100"
    fi
else
    echo ""
    echo "✗ Автоматическое добавление не удалось"
    echo ""
    echo "Добавьте ключ вручную (см. инструкции выше)"
fi

# Удаляем временный файл
rm -f "$EXPECT_SCRIPT"

echo ""
