#!/bin/bash
#
# Комплексный скрипт диагностики и исправления SSH проблем
#

set -e

VM_NAME="dns-server"
VM_IP="192.168.200.100"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║            ДИАГНОСТИКА И ИСПРАВЛЕНИЕ SSH ПРОБЛЕМЫ                            ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 1. Проверяем наличие публичного ключа
echo "[Шаг 1/5] Проверка локального SSH ключа..."
if [ ! -f "${SSH_KEY_PATH}.pub" ]; then
    echo "✗ SSH ключ не найден: ${SSH_KEY_PATH}.pub"
    echo ""
    echo "Генерируем новый SSH ключ..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "$(whoami)@$(hostname)"
    echo "✓ SSH ключ создан"
else
    echo "✓ SSH ключ найден"
fi

LOCAL_KEY_FINGERPRINT=$(ssh-keygen -lf "${SSH_KEY_PATH}.pub" | awk '{print $2}')
echo "  Fingerprint: $LOCAL_KEY_FINGERPRINT"
echo ""

# 2. Проверяем VM
echo "[Шаг 2/5] Проверка виртуальной машины..."
if ! sudo virsh list | grep -q "$VM_NAME"; then
    echo "✗ VM '$VM_NAME' не запущена"
    echo ""
    echo "Запустите VM:"
    echo "  sudo virsh start $VM_NAME"
    exit 1
fi
echo "✓ VM запущена"
echo ""

# 3. Проверяем сетевое подключение
echo "[Шаг 3/5] Проверка сетевого подключения..."
if ! ping -c 1 -W 2 "$VM_IP" &> /dev/null; then
    echo "✗ VM недоступна по сети"
    exit 1
fi
echo "✓ Сеть работает"
echo ""

# 4. Тестируем различные методы аутентификации
echo "[Шаг 4/5] Тестирование методов аутентификации..."
echo ""

# 4.1 Проверка аутентификации по ключу
echo "  [4.1] Тест аутентификации по SSH ключу..."
if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ubuntu@$VM_IP "echo 'OK'" &> /dev/null; then
    echo "  ✓ Аутентификация по ключу РАБОТАЕТ!"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           SSH УЖЕ РАБОТАЕТ!                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Команда для подключения:"
    echo "  ssh ubuntu@$VM_IP"
    echo ""
    exit 0
else
    echo "  ✗ Аутентификация по ключу НЕ работает"
fi

# 4.2 Проверка парольной аутентификации
echo "  [4.2] Тест парольной аутентификации..."
if command -v sshpass &> /dev/null; then
    if sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$VM_IP "echo 'OK'" &> /dev/null; then
        echo "  ✓ Парольная аутентификация РАБОТАЕТ!"
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                   ПАРОЛЬНАЯ АУТЕНТИФИКАЦИЯ РАБОТАЕТ                          ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Можем добавить SSH ключ через парольное подключение..."
        echo ""

        # Добавляем ключ через парольное подключение
        echo "Добавляем SSH ключ в authorized_keys..."
        LOCAL_PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")

        sshpass -p 'ubuntu' ssh -o StrictHostKeyChecking=no ubuntu@$VM_IP bash <<EOF
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo '$LOCAL_PUB_KEY' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
# Удаляем дубликаты
sort -u ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp
mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys
EOF

        echo "✓ SSH ключ добавлен"
        echo ""

        # Проверяем что ключ теперь работает
        echo "Проверяем подключение по ключу..."
        sleep 1
        if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ubuntu@$VM_IP "echo 'OK'" &> /dev/null; then
            echo "✓ Аутентификация по ключу теперь работает!"
            echo ""
            echo "╔══════════════════════════════════════════════════════════════════════════════╗"
            echo "║                          ПРОБЛЕМА РЕШЕНА!                                    ║"
            echo "╚══════════════════════════════════════════════════════════════════════════════╝"
            echo ""
            echo "Команда для подключения:"
            echo "  ssh ubuntu@$VM_IP"
            echo ""
            exit 0
        else
            echo "✗ Аутентификация по ключу всё ещё не работает"
        fi
    else
        echo "  ✗ Парольная аутентификация НЕ работает"
    fi
else
    echo "  ⚠  sshpass не установлен, пропускаем тест"
    echo "     Установите: sudo apt-get install sshpass"
fi
echo ""

# 5. Предлагаем варианты решения
echo "[Шаг 5/5] Варианты решения проблемы..."
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                       ВАРИАНТЫ РЕШЕНИЯ ПРОБЛЕМЫ                              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "У вас есть несколько вариантов:"
echo ""
echo "ВАРИАНТ 1: Добавить ключ через virsh console (рекомендуется)"
echo "  bash scripts/fix-ssh-key-via-console.sh"
echo ""
echo "ВАРИАНТ 2: Установить sshpass и повторить диагностику"
echo "  sudo apt-get install sshpass"
echo "  bash scripts/diagnose-and-fix-ssh.sh"
echo ""
echo "ВАРИАНТ 3: Пересоздать VM с текущим SSH ключом"
echo "  cd examples/local && bash ../../scripts/recreate-vm.sh"
echo ""
echo "ВАРИАНТ 4: Подключиться вручную по паролю и добавить ключ"
echo "  ssh ubuntu@$VM_IP"
echo "  (пароль: ubuntu)"
echo "  Затем на VM выполните:"
echo "    mkdir -p ~/.ssh && chmod 700 ~/.ssh"
echo "    echo '$(cat ${SSH_KEY_PATH}.pub)' >> ~/.ssh/authorized_keys"
echo "    chmod 600 ~/.ssh/authorized_keys"
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                           ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Ваш публичный ключ:"
echo "  $(cat ${SSH_KEY_PATH}.pub)"
echo ""
echo "Fingerprint:"
echo "  $LOCAL_KEY_FINGERPRINT"
echo ""
