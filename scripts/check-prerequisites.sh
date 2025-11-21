#!/bin/bash

# Скрипт для проверки всех необходимых зависимостей
# перед запуском Terraform для развертывания DNS сервера

set -e

echo "🔍 Проверка предварительных требований для развертывания DNS сервера..."
echo ""

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Функция проверки команды
check_command() {
    local cmd=$1
    local package=$2
    local critical=${3:-true}

    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}✅${NC} $cmd найден: $(command -v $cmd)"
        return 0
    else
        if [ "$critical" = true ]; then
            echo -e "${RED}❌${NC} $cmd не найден"
            echo -e "   ${YELLOW}Установите:${NC} apt-get install -y $package"
            ERRORS=$((ERRORS + 1))
            return 1
        else
            echo -e "${YELLOW}⚠️${NC}  $cmd не найден (опционально)"
            echo -e "   Рекомендуется: apt-get install -y $package"
            WARNINGS=$((WARNINGS + 1))
            return 0
        fi
    fi
}

# Функция проверки версии
check_version() {
    local cmd=$1
    local min_version=$2

    if command -v "$cmd" &> /dev/null; then
        local version=$($cmd --version 2>&1 | head -1)
        echo -e "   ${GREEN}Версия:${NC} $version"
    fi
}

echo "📦 Проверка основных утилит:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Критичные зависимости
check_command "terraform" "terraform" true
check_version "terraform" "1.0"

check_command "virsh" "libvirt-clients" true
check_command "qemu-system-x86_64" "qemu-kvm" true

# КРИТИЧНО: xsltproc требуется для применения XSLT трансформаций в libvirt provider
# Без него трансформация security labels не работает, что приводит к Permission denied
check_command "xsltproc" "xsltproc" true
if command -v xsltproc &> /dev/null; then
    check_version "xsltproc" ""
    echo -e "   ${GREEN}ℹ️${NC}  xsltproc требуется для libvirt provider (XSLT трансформации)"
fi

check_command "ssh" "openssh-client" true
check_command "ssh-keygen" "openssh-client" true

echo ""
echo "🌐 Проверка сетевых утилит:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_command "dig" "dnsutils" false
check_command "nsupdate" "dnsutils" false
check_command "curl" "curl" false

echo ""
echo "🔐 Проверка SSH ключей:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    echo -e "${GREEN}✅${NC} SSH ключ найден: $HOME/.ssh/id_rsa.pub"
elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    echo -e "${GREEN}✅${NC} SSH ключ найден: $HOME/.ssh/id_ed25519.pub"
else
    echo -e "${YELLOW}⚠️${NC}  SSH ключ не найден"
    echo -e "   Создайте ключ: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N \"\""
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "🖥️  Проверка libvirt:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Проверка доступности libvirt
if command -v virsh &> /dev/null; then
    if virsh version &> /dev/null 2>&1; then
        echo -e "${GREEN}✅${NC} libvirt доступен"
        virsh version 2>&1 | grep -E "(Compiled|Running|Using)" | sed 's/^/   /'
    else
        echo -e "${RED}❌${NC} libvirt не доступен (проверьте права доступа)"
        echo -e "   Добавьте пользователя в группу: usermod -a -G libvirt \$(whoami)"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Проверка пула по умолчанию
if command -v virsh &> /dev/null; then
    if virsh pool-list --all &> /dev/null 2>&1; then
        echo -e "${GREEN}✅${NC} libvirt storage pools доступны"
    fi
fi

echo ""
echo "📊 Результаты проверки:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ Все проверки пройдены успешно!${NC}"
    echo ""
    echo "🚀 Можно запускать Terraform:"
    echo "   cd examples/local"
    echo "   terraform init"
    echo "   terraform apply"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Найдено предупреждений: $WARNINGS${NC}"
    echo -e "${GREEN}✅ Критичных ошибок не обнаружено${NC}"
    echo ""
    echo "🚀 Можно запускать Terraform (с предупреждениями):"
    echo "   cd examples/local"
    echo "   terraform init"
    echo "   terraform apply"
    exit 0
else
    echo -e "${RED}❌ Обнаружено критичных ошибок: $ERRORS${NC}"
    echo -e "${YELLOW}⚠️  Предупреждений: $WARNINGS${NC}"
    echo ""
    echo "❗ Установите недостающие пакеты перед запуском Terraform"
    echo ""
    echo "Команда для установки всех зависимостей на Ubuntu/Debian:"
    echo "   apt-get update"
    echo "   apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils xsltproc dnsutils curl openssh-client"
    echo ""
    echo "Также необходимо:"
    echo "   usermod -a -G libvirt \$(whoami)"
    echo "   newgrp libvirt"
    exit 1
fi
