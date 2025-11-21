#!/bin/bash
set -e

echo "=== Безопасное исправление libvirt QEMU permissions ==="
echo ""
echo "Этот скрипт предлагает более безопасный подход, чем запуск от root."
echo ""

# Найти конфигурационный файл qemu.conf
QEMU_CONF=""
for path in /etc/libvirt/qemu.conf /usr/local/etc/libvirt/qemu.conf; do
    if [ -f "$path" ]; then
        QEMU_CONF="$path"
        break
    fi
done

if [ -z "$QEMU_CONF" ]; then
    echo "ERROR: qemu.conf not found!"
    echo "Searching for libvirt config files..."
    find /etc -name "*libvirt*" -type d 2>/dev/null || true
    exit 1
fi

echo "Found qemu.conf: $QEMU_CONF"
echo ""

# Определяем пользователя QEMU
QEMU_USER="libvirt-qemu"
if ! id "$QEMU_USER" &>/dev/null; then
    # Попробуем альтернативные имена
    if id "qemu" &>/dev/null; then
        QEMU_USER="qemu"
    elif id "libvirt" &>/dev/null; then
        QEMU_USER="libvirt"
    else
        echo "WARNING: Could not find QEMU user (libvirt-qemu, qemu, or libvirt)"
        QEMU_USER="libvirt-qemu"
    fi
fi

echo "QEMU user will be: $QEMU_USER"
echo ""

# Выбор режима безопасности
echo "Выберите режим безопасности:"
echo ""
echo "1) БЕЗОПАСНЫЙ (рекомендуется для продакшн)"
echo "   - QEMU запускается от $QEMU_USER (не root)"
echo "   - dynamic_ownership = 1 (автоматическое управление правами)"
echo "   - Права на pool директорию настраиваются автоматически"
echo "   - AppArmor остается включенным, но настроен правильно"
echo ""
echo "2) КОМПРОМИССНЫЙ (для разработки)"
echo "   - QEMU запускается от $QEMU_USER"
echo "   - dynamic_ownership = 1"
echo "   - security_driver = 'none' (отключает AppArmor для libvirt)"
echo ""
echo "3) НЕБЕЗОПАСНЫЙ (быстрое решение, НЕ для продакшн!)"
echo "   - QEMU запускается от root (ОПАСНО!)"
echo "   - security_driver = 'none'"
echo "   - Все ограничения отключены"
echo ""

read -p "Ваш выбор [1/2/3]: " CHOICE

# Бэкап конфигурационного файла
BACKUP_FILE="${QEMU_CONF}.backup.$(date +%Y%m%d-%H%M%S)"
sudo cp "$QEMU_CONF" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"
echo ""

# Применяем настройки в зависимости от выбора
case $CHOICE in
    1)
        echo "=== Применение БЕЗОПАСНЫХ настроек ==="

        # Удаляем старые настройки
        sudo sed -i '/^user = /d' "$QEMU_CONF"
        sudo sed -i '/^group = /d' "$QEMU_CONF"
        sudo sed -i '/^dynamic_ownership = /d' "$QEMU_CONF"
        sudo sed -i '/^security_driver = /d' "$QEMU_CONF"

        # Добавляем безопасные настройки
        sudo tee -a "$QEMU_CONF" > /dev/null << EOF

# Added by fix-libvirt-permissions-safe.sh (SECURE mode)
user = "$QEMU_USER"
group = "$QEMU_USER"
dynamic_ownership = 1
# security_driver оставляем по умолчанию (AppArmor включен)
EOF

        # Настраиваем права на pool директорию
        POOL_DIR="/var/lib/libvirt/pools/dns-server"
        if [ -d "$POOL_DIR" ]; then
            echo "Настройка прав на $POOL_DIR..."
            sudo chown -R "$QEMU_USER:$QEMU_USER" "$POOL_DIR"
            sudo chmod 755 "$POOL_DIR"
            sudo find "$POOL_DIR" -type f -name "*.qcow2" -exec chmod 644 {} \;
        fi

        # Настраиваем права на images директорию
        IMAGES_DIR="/var/lib/libvirt/images"
        if [ -d "$IMAGES_DIR" ]; then
            echo "Настройка прав на $IMAGES_DIR..."
            sudo chown "$QEMU_USER:$QEMU_USER" "$IMAGES_DIR"
            sudo chmod 755 "$IMAGES_DIR"
        fi

        echo ""
        echo "✅ БЕЗОПАСНЫЙ режим применен"
        echo "   - QEMU работает от $QEMU_USER (не root)"
        echo "   - AppArmor остается активным"
        echo "   - Права на директории настроены"
        ;;

    2)
        echo "=== Применение КОМПРОМИССНЫХ настроек ==="

        sudo sed -i '/^user = /d' "$QEMU_CONF"
        sudo sed -i '/^group = /d' "$QEMU_CONF"
        sudo sed -i '/^dynamic_ownership = /d' "$QEMU_CONF"
        sudo sed -i '/^security_driver = /d' "$QEMU_CONF"

        sudo tee -a "$QEMU_CONF" > /dev/null << EOF

# Added by fix-libvirt-permissions-safe.sh (COMPROMISE mode)
user = "$QEMU_USER"
group = "$QEMU_USER"
dynamic_ownership = 1
security_driver = "none"
EOF

        echo ""
        echo "⚠️  КОМПРОМИССНЫЙ режим применен"
        echo "   - QEMU работает от $QEMU_USER"
        echo "   - AppArmor отключен (security_driver = none)"
        ;;

    3)
        echo "=== Применение НЕБЕЗОПАСНЫХ настроек ==="
        echo "⚠️⚠️⚠️  ВНИМАНИЕ: Это снижает безопасность системы!"

        sudo sed -i '/^user = /d' "$QEMU_CONF"
        sudo sed -i '/^group = /d' "$QEMU_CONF"
        sudo sed -i '/^dynamic_ownership = /d' "$QEMU_CONF"
        sudo sed -i '/^security_driver = /d' "$QEMU_CONF"

        sudo tee -a "$QEMU_CONF" > /dev/null << EOF

# Added by fix-libvirt-permissions-safe.sh (INSECURE mode - NOT for production!)
user = "root"
group = "root"
dynamic_ownership = 1
security_driver = "none"
EOF

        echo ""
        echo "🔴 НЕБЕЗОПАСНЫЙ режим применен"
        echo "   - QEMU работает от ROOT (ОПАСНО!)"
        echo "   - AppArmor полностью отключен"
        echo "   - НЕ ИСПОЛЬЗУЙТЕ на production серверах!"
        ;;

    *)
        echo "ERROR: Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "Configuration applied:"
grep -E "^(user|group|dynamic_ownership|security_driver)" "$QEMU_CONF" || echo "(using defaults)"

# Перезапуск libvirtd
echo ""
echo "Restarting libvirtd..."
sudo systemctl restart libvirtd
sleep 2

# Проверка статуса
sudo systemctl status libvirtd --no-pager | head -10

echo ""
echo "=== Fix applied successfully! ==="
echo ""
echo "Следующие шаги:"
echo "1. cd examples/local"
echo "2. terraform apply"
echo ""
if [ "$CHOICE" = "3" ]; then
    echo "⚠️  Напоминание: Вы используете небезопасный режим!"
    echo "   Рассмотрите переход на безопасный режим (опция 1) для продакшн."
fi
