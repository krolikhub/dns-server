#!/bin/bash
set -e

echo "=== Fixing libvirt QEMU permissions ==="

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

# Бэкап конфигурационного файла
sudo cp "$QEMU_CONF" "${QEMU_CONF}.backup.$(date +%Y%m%d-%H%M%S)"

# Настройка параметров
echo "Configuring security settings..."

# Удаляем старые настройки (если есть) и добавляем новые
sudo sed -i '/^user = /d' "$QEMU_CONF"
sudo sed -i '/^group = /d' "$QEMU_CONF"
sudo sed -i '/^dynamic_ownership = /d' "$QEMU_CONF"
sudo sed -i '/^security_driver = /d' "$QEMU_CONF"

# Добавляем настройки в конец файла
sudo tee -a "$QEMU_CONF" > /dev/null << 'EOF'

# Added by fix-libvirt-permissions.sh
user = "root"
group = "root"
dynamic_ownership = 1
security_driver = "none"
EOF

echo "Configuration updated:"
grep -E "^(user|group|dynamic_ownership|security_driver)" "$QEMU_CONF"

# Перезапуск libvirtd
echo "Restarting libvirtd..."
sudo systemctl restart libvirtd
sleep 2

# Проверка статуса
sudo systemctl status libvirtd --no-pager | head -10

echo ""
echo "=== Fix applied successfully! ==="
echo "You can now run: terraform apply"
