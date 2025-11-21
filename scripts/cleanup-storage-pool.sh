#!/bin/bash

# Скрипт для очистки libvirt storage pool при ошибке "Directory not empty"
# Использование: sudo ./scripts/cleanup-storage-pool.sh [pool-name] [pool-path]

set -e

POOL_NAME="${1:-dns-server-pool}"
POOL_PATH="${2:-/var/lib/libvirt/pools/dns-server}"
VM_NAME="${3:-dns-server}"

echo "=== Очистка libvirt storage pool ==="
echo "Pool name: $POOL_NAME"
echo "Pool path: $POOL_PATH"
echo "VM name: $VM_NAME"
echo

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Скрипт должен запускаться от root"
  echo "Используйте: sudo $0 $@"
  exit 1
fi

# Функция для безопасного выполнения команд virsh
safe_virsh() {
  local cmd="$1"
  local resource="$2"

  if virsh "$cmd" "$resource" 2>&1 | grep -qE "(not found|does not exist)"; then
    echo "  ℹ️  $resource не существует, пропускаем"
    return 0
  fi

  virsh "$cmd" "$resource" 2>/dev/null || true
  return 0
}

echo "1️⃣  Остановка и удаление виртуальной машины..."
if virsh list --all | grep -q "$VM_NAME"; then
  echo "  Найдена VM: $VM_NAME"
  safe_virsh destroy "$VM_NAME"
  safe_virsh undefine "$VM_NAME"
  echo "  ✅ VM удалена"
else
  echo "  ℹ️  VM не найдена"
fi

echo
echo "2️⃣  Удаление volumes из pool..."
if virsh pool-info "$POOL_NAME" &>/dev/null; then
  # Refresh pool чтобы получить актуальный список volumes
  virsh pool-refresh "$POOL_NAME" 2>/dev/null || true

  # Получить список volumes
  VOLUMES=$(virsh vol-list "$POOL_NAME" 2>/dev/null | tail -n +3 | awk '{print $1}' | grep -v '^$')

  if [ -n "$VOLUMES" ]; then
    echo "$VOLUMES" | while read vol; do
      if [ -n "$vol" ]; then
        echo "  Удаление volume: $vol"
        virsh vol-delete "$vol" --pool "$POOL_NAME" 2>/dev/null || true
      fi
    done
    echo "  ✅ Volumes удалены"
  else
    echo "  ℹ️  Volumes не найдены"
  fi
else
  echo "  ℹ️  Pool не найден в libvirt"
fi

echo
echo "3️⃣  Удаление файлов из директории pool..."
if [ -d "$POOL_PATH" ]; then
  echo "  Содержимое директории:"
  ls -lah "$POOL_PATH" | tail -n +2 || true

  FILE_COUNT=$(ls -A "$POOL_PATH" | wc -l)
  if [ "$FILE_COUNT" -gt 0 ]; then
    echo "  Найдено файлов: $FILE_COUNT"
    echo "  Удаление файлов..."
    rm -rf "${POOL_PATH:?}"/*
    echo "  ✅ Файлы удалены"
  else
    echo "  ℹ️  Директория пуста"
  fi
else
  echo "  ℹ️  Директория не существует"
fi

echo
echo "4️⃣  Удаление директории pool..."
if [ -d "$POOL_PATH" ]; then
  if rmdir "$POOL_PATH" 2>/dev/null; then
    echo "  ✅ Директория удалена"
  else
    echo "  ⚠️  Не удалось удалить директорию (возможно не пуста)"
    ls -la "$POOL_PATH" || true
  fi
else
  echo "  ℹ️  Директория не существует"
fi

echo
echo "5️⃣  Удаление pool из libvirt..."
if virsh pool-info "$POOL_NAME" &>/dev/null; then
  safe_virsh pool-destroy "$POOL_NAME"
  safe_virsh pool-undefine "$POOL_NAME"
  echo "  ✅ Pool удален из libvirt"
else
  echo "  ℹ️  Pool не найден в libvirt"
fi

echo
echo "6️⃣  Проверка результата..."
if [ -d "$POOL_PATH" ]; then
  echo "  ❌ Директория все еще существует"
  exit 1
else
  echo "  ✅ Директория успешно удалена"
fi

if virsh pool-info "$POOL_NAME" &>/dev/null; then
  echo "  ⚠️  Pool все еще существует в libvirt"
else
  echo "  ✅ Pool удален из libvirt"
fi

echo
echo "✅ Очистка завершена!"
echo
echo "Следующие шаги:"
echo "1. Удалите pool из состояния Terraform:"
echo "   cd examples/local && terraform state rm module.dns_server.libvirt_pool.vm_pool"
echo
echo "2. Завершите terraform destroy:"
echo "   terraform destroy"
