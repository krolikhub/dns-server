#!/bin/bash
# Скрипт для очистки существующего libvirt домена dns-server
# Используется когда Terraform выдает ошибку "domain already exists"

set -e

DOMAIN_NAME="${1:-dns-server}"

echo "🔍 Проверка статуса домена '$DOMAIN_NAME'..."

# Проверяем существует ли домен
if ! virsh dominfo "$DOMAIN_NAME" &>/dev/null; then
    echo "✅ Домен '$DOMAIN_NAME' не найден. Всё чисто!"
    exit 0
fi

# Показываем информацию о домене
echo "📋 Информация о существующем домене:"
virsh dominfo "$DOMAIN_NAME" || true

# Проверяем статус
STATE=$(virsh domstate "$DOMAIN_NAME" 2>/dev/null || echo "unknown")
echo "📊 Текущий статус: $STATE"

# Останавливаем домен если он запущен
if [ "$STATE" = "running" ] || [ "$STATE" = "paused" ]; then
    echo "🛑 Останавливаем домен..."
    virsh destroy "$DOMAIN_NAME" || echo "⚠️  Не удалось остановить (возможно уже остановлен)"
fi

# Удаляем домен и все связанное хранилище
echo "🗑️  Удаляем домен и связанные ресурсы..."
virsh undefine "$DOMAIN_NAME" --remove-all-storage || \
    virsh undefine "$DOMAIN_NAME" --nvram --remove-all-storage 2>/dev/null || \
    virsh undefine "$DOMAIN_NAME"

echo "✅ Домен '$DOMAIN_NAME' успешно удален!"
echo ""
echo "Теперь можно запустить: terraform apply"
