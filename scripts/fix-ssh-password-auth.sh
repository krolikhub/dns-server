#!/bin/bash
#
# Скрипт для исправления SSH парольной аутентификации на Ubuntu 22.04 с cloud-init
#
# ПРОБЛЕМА:
# Cloud-init создает /etc/ssh/sshd_config.d/50-cloud-init.conf который может
# содержать PasswordAuthentication no, и этот файл имеет приоритет над основным
# sshd_config, так как SSH читает конфиги в алфавитном порядке и ПЕРВАЯ
# найденная директива побеждает!
#
# РЕШЕНИЕ:
# 1. Создаем /etc/ssh/sshd_config.d/01-custom-auth.conf с правильными настройками
# 2. Удаляем конфликтующий 50-cloud-init.conf
# 3. Обновляем основной sshd_config
# 4. Перезапускаем SSH сервис
#

set -e

echo "=========================================="
echo "Fixing SSH Password Authentication"
echo "=========================================="
echo ""

# Проверяем что скрипт запущен с правами root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)"
  exit 1
fi

# Показываем текущую конфигурацию
echo "[1/6] Current SSH configuration:"
echo "---"
sshd -T | grep -E '(passwordauthentication|permitrootlogin|kbdinteractiveauthentication|pubkeyauthentication)'
echo ""

echo "[2/6] Current config files in sshd_config.d/:"
echo "---"
ls -la /etc/ssh/sshd_config.d/ 2>/dev/null || echo "No config files found"
echo ""

# Создаем приоритетный конфиг файл (01- будет прочитан первым!)
echo "[3/6] Creating priority SSH config file: /etc/ssh/sshd_config.d/01-custom-auth.conf"
cat > /etc/ssh/sshd_config.d/01-custom-auth.conf <<'EOF'
# Custom SSH configuration for password authentication
# This file has priority over 50-cloud-init.conf (read first in alphabetical order)
# In SSH config, the FIRST matching directive wins!

PasswordAuthentication yes
PermitRootLogin yes
ChallengeResponseAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
UsePAM yes
EOF

chmod 644 /etc/ssh/sshd_config.d/01-custom-auth.conf
echo "✓ Created 01-custom-auth.conf"
echo ""

# Удаляем конфликтующий cloud-init конфиг
echo "[4/6] Removing conflicting cloud-init config:"
if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]; then
    echo "Backing up 50-cloud-init.conf to /root/50-cloud-init.conf.backup"
    cp /etc/ssh/sshd_config.d/50-cloud-init.conf /root/50-cloud-init.conf.backup
    rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
    echo "✓ Removed 50-cloud-init.conf"
else
    echo "✓ No 50-cloud-init.conf found (already removed)"
fi
echo ""

# Обновляем основной sshd_config (на всякий случай)
echo "[5/6] Updating main sshd_config:"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
echo "✓ Updated /etc/ssh/sshd_config"
echo ""

# Проверяем синтаксис конфигурации
echo "[6/6] Testing SSH configuration syntax:"
if sshd -t; then
    echo "✓ SSH configuration syntax is valid"
else
    echo "✗ ERROR: SSH configuration has syntax errors!"
    exit 1
fi
echo ""

# Перезапускаем SSH
echo "Restarting SSH service..."
systemctl restart ssh
sleep 2

if systemctl is-active --quiet ssh; then
    echo "✓ SSH service restarted successfully"
else
    echo "✗ ERROR: SSH service failed to start!"
    systemctl status ssh
    exit 1
fi
echo ""

# Показываем итоговую конфигурацию
echo "=========================================="
echo "FINAL SSH CONFIGURATION:"
echo "=========================================="
echo ""
echo "Effective SSH configuration:"
sshd -T | grep -E '(passwordauthentication|permitrootlogin|kbdinteractiveauthentication|pubkeyauthentication)'
echo ""
echo "Config files in sshd_config.d/:"
ls -la /etc/ssh/sshd_config.d/
echo ""
echo "=========================================="
echo "✓ SSH Password Authentication is now ENABLED!"
echo "=========================================="
echo ""
echo "You can now login using:"
echo "  ssh ubuntu@<server-ip>"
echo ""
echo "NOTE: Make sure the ubuntu user has a password set!"
echo "To set password: sudo passwd ubuntu"
echo ""
