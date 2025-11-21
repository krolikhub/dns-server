#!/bin/bash

# =============================================================================
# СКРИПТ ДЛЯ ИСПРАВЛЕНИЯ SSH КЛЮЧЕЙ НА VM
# =============================================================================
# Этот скрипт исправляет проблему когда SSH ключи не работают для подключения
# =============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Символы
CHECKMARK="${GREEN}✓${NC}"
CROSSMARK="${RED}✗${NC}"
INFO="${BLUE}ℹ${NC}"
WARNING="${YELLOW}⚠${NC}"

# Параметры
VM_IP="${1:-192.168.200.100}"
VM_USER="${2:-ubuntu}"
VM_PASSWORD="${3:-ubuntu}"
LOCAL_PUBLIC_KEY="${4:-$HOME/.ssh/id_rsa.pub}"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    ИСПРАВЛЕНИЕ SSH КЛЮЧЕЙ НА VM                             ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Проверка наличия публичного ключа
if [ ! -f "$LOCAL_PUBLIC_KEY" ]; then
    echo -e "${CROSSMARK} Публичный ключ не найден: $LOCAL_PUBLIC_KEY"
    echo -e "${INFO} Создайте SSH ключ командой: ssh-keygen -t rsa -b 4096"
    exit 1
fi

echo -e "${INFO} Используемый публичный ключ: $LOCAL_PUBLIC_KEY"
echo -e "${INFO} Содержимое ключа:"
cat "$LOCAL_PUBLIC_KEY"
echo ""

# Проверка наличия sshpass
if ! command -v sshpass &> /dev/null; then
    echo -e "${WARNING} sshpass не установлен"
    echo -e "${INFO} Попробуем установить..."

    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y sshpass
    elif command -v yum &> /dev/null; then
        sudo yum install -y sshpass
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y sshpass
    else
        echo -e "${CROSSMARK} Не удалось установить sshpass автоматически"
        echo -e "${INFO} Установите вручную: sudo apt-get install sshpass"
        exit 1
    fi
fi

echo -e "${CHECKMARK} sshpass установлен"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║ ШАГ 1: ПРОВЕРКА ПОДКЛЮЧЕНИЯ ПО ПАРОЛЮ"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Функция для выполнения команд на VM через SSH с паролем
ssh_exec() {
    sshpass -p "$VM_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        -o ConnectTimeout=10 \
        "$VM_USER@$VM_IP" "$@" 2>&1
}

# Проверка подключения
if ! ssh_exec "echo 'Connection OK'" | grep -q "Connection OK"; then
    echo -e "${CROSSMARK} Не удалось подключиться по паролю"
    echo -e "${INFO} Проверьте:"
    echo "  - VM запущена: virsh list --all"
    echo "  - Доступна по сети: ping $VM_IP"
    echo "  - Правильный пароль: $VM_PASSWORD"
    exit 1
fi

echo -e "${CHECKMARK} Подключение по паролю работает"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║ ШАГ 2: ПРОВЕРКА ТЕКУЩЕГО СОСТОЯНИЯ"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${INFO} Проверяем директорию .ssh..."
ssh_exec "ls -la ~/.ssh/ 2>&1 || echo 'Directory does not exist'"
echo ""

echo -e "${INFO} Текущее содержимое authorized_keys (если есть):"
CURRENT_KEYS=$(ssh_exec "cat ~/.ssh/authorized_keys 2>&1 || echo 'File does not exist'")
echo "$CURRENT_KEYS"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║ ШАГ 3: ИСПРАВЛЕНИЕ AUTHORIZED_KEYS"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${INFO} Создаем директорию .ssh если не существует..."
ssh_exec "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
echo -e "${CHECKMARK} Директория .ssh создана"
echo ""

echo -e "${INFO} Добавляем публичный ключ в authorized_keys..."
PUBLIC_KEY_CONTENT=$(cat "$LOCAL_PUBLIC_KEY")
ssh_exec "echo '$PUBLIC_KEY_CONTENT' >> ~/.ssh/authorized_keys"
echo -e "${CHECKMARK} Ключ добавлен"
echo ""

echo -e "${INFO} Устанавливаем правильные права доступа..."
ssh_exec "chmod 600 ~/.ssh/authorized_keys"
echo -e "${CHECKMARK} Права установлены"
echo ""

echo -e "${INFO} Удаляем дубликаты ключей..."
ssh_exec "sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys"
echo -e "${CHECKMARK} Дубликаты удалены"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║ ШАГ 4: ПРОВЕРКА РЕЗУЛЬТАТА"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${INFO} Новое содержимое authorized_keys:"
ssh_exec "cat ~/.ssh/authorized_keys"
echo ""

echo -e "${INFO} Права доступа к файлам:"
ssh_exec "ls -la ~/.ssh/"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║ ШАГ 5: ТЕСТ ПОДКЛЮЧЕНИЯ ПО КЛЮЧУ"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${INFO} Пробуем подключиться по ключу..."
sleep 2  # Даем системе время обработать изменения

PRIVATE_KEY="${LOCAL_PUBLIC_KEY%.pub}"
if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "$VM_USER@$VM_IP" "echo 'SSH KEY AUTH WORKS!'" 2>&1 | grep -q "SSH KEY AUTH WORKS"; then
    echo -e "${CHECKMARK} ${GREEN}УСПЕХ! SSH подключение по ключу работает!${NC}"
    echo ""
    echo -e "${INFO} Теперь вы можете подключаться командой:"
    echo "  ssh -i $PRIVATE_KEY $VM_USER@$VM_IP"
    echo ""
    echo "  Или просто:"
    echo "  ssh $VM_USER@$VM_IP"
    echo ""
else
    echo -e "${WARNING} Подключение по ключу все еще не работает"
    echo ""
    echo -e "${INFO} Возможные причины:"
    echo "  1. SSH агент использует другой ключ"
    echo "  2. Проблема с правами на стороне сервера"
    echo "  3. SSH конфигурация сервера блокирует ключи"
    echo ""
    echo -e "${INFO} Дополнительная диагностика:"
    echo "  - Проверьте SSH конфигурацию на VM:"
    ssh_exec "sudo sshd -T | grep -E '(pubkeyauth|authorizedkeys)'"
    echo ""
    echo "  - Попробуйте подключиться с debug:"
    echo "    ssh -vvv -i $PRIVATE_KEY $VM_USER@$VM_IP"
    echo ""
fi

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                              ГОТОВО!                                         ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
