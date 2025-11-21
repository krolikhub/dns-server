#!/bin/bash
#
# Скрипт для сброса пароля пользователя ubuntu через virt-customize
#
# ИСПОЛЬЗОВАНИЕ:
#   ./fix-vm-console-password.sh [VM_NAME] [USERNAME] [PASSWORD]
#
# ПРИМЕР:
#   ./fix-vm-console-password.sh dns-server ubuntu ubuntu
#

set -e

VM_NAME="${1:-dns-server}"
USERNAME="${2:-ubuntu}"
PASSWORD="${3:-ubuntu}"

echo "=========================================="
echo "Сброс пароля для VM: $VM_NAME"
echo "=========================================="
echo ""
echo "VM Name:  $VM_NAME"
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
echo ""

# Проверка наличия libguestfs-tools
if ! command -v virt-customize &> /dev/null; then
    echo "❌ ОШИБКА: virt-customize не найден!"
    echo ""
    echo "Установите libguestfs-tools:"
    echo "  sudo apt-get install -y libguestfs-tools"
    echo ""
    exit 1
fi

# Проверка что VM существует
if ! sudo virsh dominfo "$VM_NAME" &> /dev/null; then
    echo "❌ ОШИБКА: VM '$VM_NAME' не найдена!"
    echo ""
    echo "Доступные VM:"
    sudo virsh list --all
    echo ""
    exit 1
fi

# Показать текущее состояние VM
echo "Текущее состояние VM:"
sudo virsh domstate "$VM_NAME"
echo ""

# Остановка VM
echo "[1/4] Остановка VM $VM_NAME..."
if sudo virsh domstate "$VM_NAME" | grep -q "running"; then
    sudo virsh shutdown "$VM_NAME" 2>/dev/null || true
    echo "Ожидание остановки VM (10 секунд)..."
    sleep 10

    # Проверка что VM остановлена
    if sudo virsh domstate "$VM_NAME" | grep -q "running"; then
        echo "⚠️  VM все еще работает, принудительное выключение..."
        sudo virsh destroy "$VM_NAME"
        sleep 3
    fi
fi

echo "✓ VM остановлена"
echo ""

# Сброс пароля
echo "[2/4] Сброс пароля пользователя $USERNAME..."
echo ""
echo "Выполняется: sudo virt-customize -d $VM_NAME --password ${USERNAME}:password:${PASSWORD}"
echo ""

# Показываем вывод virt-customize для диагностики
sudo virt-customize -d "$VM_NAME" --password "${USERNAME}:password:${PASSWORD}"

echo ""
echo "✓ Пароль изменен"
echo ""

# Запуск VM
echo "[3/4] Запуск VM..."
sudo virsh start "$VM_NAME"
echo "✓ VM запущена"
echo ""

# Ожидание загрузки
echo "[4/4] Ожидание загрузки VM (30 секунд)..."
for i in {1..30}; do
    echo -n "."
    sleep 1
done
echo ""
echo ""

echo "=========================================="
echo "✓ Готово!"
echo "=========================================="
echo ""
echo "Пароль для пользователя '$USERNAME' изменен на: $PASSWORD"
echo ""
echo "Теперь вы можете подключиться:"
echo ""
echo "  sudo virsh console $VM_NAME"
echo ""
echo "Логин:  $USERNAME"
echo "Пароль: $PASSWORD"
echo ""
echo "Для выхода из консоли нажмите: Ctrl + ]"
echo ""
echo "Также можно подключиться по SSH:"
echo "  ssh ${USERNAME}@192.168.200.100"
echo ""
