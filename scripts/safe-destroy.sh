#!/bin/bash

# Скрипт для безопасного удаления DNS сервера с подтверждением
# Использование: ./scripts/safe-destroy.sh [--yes]

set -e

# Цвета для вывода
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Параметры
AUTO_YES=false
if [ "$1" == "--yes" ] || [ "$1" == "-y" ]; then
  AUTO_YES=true
fi

echo -e "${BLUE}=== DNS Server Safe Destroy Script ===${NC}"
echo

# Проверка что мы в правильной директории
if [ ! -f "main.tf" ]; then
  echo -e "${RED}Error: main.tf not found${NC}"
  echo "Please run this script from examples/local directory"
  echo "Usage: cd examples/local && ../../scripts/safe-destroy.sh"
  exit 1
fi

echo -e "${YELLOW}⚠️  WARNING: This will destroy all resources including:${NC}"
echo "  - Virtual Machine (VM)"
echo "  - Network interfaces"
echo "  - Storage volumes (VM disks, base images)"
echo "  - Cloud-init disks"
echo "  - Storage pool directory"
echo "  - Network configuration"
echo

# Показать текущие ресурсы
echo -e "${BLUE}Current resources:${NC}"
terraform state list 2>/dev/null | grep -E "libvirt|random" | sed 's/^/  - /'
echo

# Запросить подтверждение
if [ "$AUTO_YES" = false ]; then
  echo -e "${RED}Do you really want to destroy all resources?${NC}"
  echo -e "${YELLOW}This action cannot be undone. Type 'yes' to confirm:${NC}"
  read -r CONFIRMATION

  if [ "$CONFIRMATION" != "yes" ]; then
    echo -e "${GREEN}Destroy cancelled.${NC}"
    exit 0
  fi
fi

echo
echo -e "${BLUE}Starting safe destroy process...${NC}"
echo

# Функция для выполнения terraform destroy с обработкой ошибок
destroy_resource() {
  local resource="$1"
  local description="$2"

  echo -e "${BLUE}[$description]${NC}"

  if terraform state list 2>/dev/null | grep -q "$resource"; then
    echo "  Destroying: $resource"
    if terraform destroy -target="$resource" -auto-approve; then
      echo -e "  ${GREEN}✓ Success${NC}"
    else
      echo -e "  ${YELLOW}⚠ Failed, continuing...${NC}"
    fi
  else
    echo -e "  ${YELLOW}ℹ Resource not found in state, skipping${NC}"
  fi
  echo
}

# Шаг 1: Удаление VM (домена)
destroy_resource \
  "module.dns_server.libvirt_domain.dns_server" \
  "1/6 Destroying Virtual Machine"

# Шаг 2: Удаление cloudinit диска
destroy_resource \
  "module.dns_server.libvirt_cloudinit_disk.cloudinit" \
  "2/6 Destroying Cloud-init disk"

# Шаг 3: Удаление диска VM
destroy_resource \
  "module.dns_server.libvirt_volume.dns_server" \
  "3/6 Destroying VM disk"

# Шаг 4: Удаление базового образа
destroy_resource \
  "module.dns_server.libvirt_volume.base" \
  "4/6 Destroying base image"

# Шаг 5: Удаление storage pool
destroy_resource \
  "module.dns_server.libvirt_pool.vm_pool" \
  "5/6 Destroying storage pool"

# Шаг 6: Удаление сети
destroy_resource \
  "module.dns_server.libvirt_network.dns_network" \
  "6/6 Destroying network"

echo -e "${BLUE}Final cleanup: Destroying remaining resources...${NC}"
echo

# Финальная очистка - удаление всех оставшихся ресурсов
if terraform destroy -auto-approve; then
  echo
  echo -e "${GREEN}✅ All resources destroyed successfully!${NC}"
  echo
else
  echo
  echo -e "${YELLOW}⚠️  Some resources may not have been destroyed.${NC}"
  echo
  echo "If you encountered 'Directory not empty' error, run:"
  echo -e "${BLUE}  sudo ../../scripts/cleanup-storage-pool.sh${NC}"
  echo -e "${BLUE}  terraform state rm module.dns_server.libvirt_pool.vm_pool${NC}"
  echo -e "${BLUE}  terraform destroy${NC}"
  echo
  exit 1
fi

# Проверка результата
echo -e "${BLUE}Verifying cleanup...${NC}"
REMAINING=$(terraform state list 2>/dev/null | grep -E "libvirt" | wc -l)

if [ "$REMAINING" -eq 0 ]; then
  echo -e "${GREEN}✓ All libvirt resources removed from state${NC}"
else
  echo -e "${YELLOW}⚠ $REMAINING libvirt resource(s) still in state:${NC}"
  terraform state list | grep -E "libvirt" | sed 's/^/  - /'
fi

echo
echo -e "${GREEN}Done!${NC}"
