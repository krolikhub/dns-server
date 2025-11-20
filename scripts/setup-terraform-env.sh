#!/bin/bash

# Скрипт для настройки окружения Terraform
# Решает проблемы с прокси для доступа к registry.terraform.io

set -e

echo "🔧 Настройка окружения для Terraform..."

# Проверка наличия прокси переменных
if [ -n "$HTTPS_PROXY" ] || [ -n "$HTTP_PROXY" ]; then
    echo "✅ Обнаружены прокси настройки:"
    echo "   HTTP_PROXY: ${HTTP_PROXY:-не установлен}"
    echo "   HTTPS_PROXY: ${HTTPS_PROXY:-не установлен}"
    echo "   NO_PROXY: ${NO_PROXY:-не установлен}"

    # Добавляем registry.terraform.io и releases.hashicorp.com в NO_PROXY
    if [[ ! "$NO_PROXY" =~ "registry.terraform.io" ]]; then
        export NO_PROXY="${NO_PROXY},registry.terraform.io,releases.hashicorp.com"
        echo ""
        echo "✅ Добавлены исключения в NO_PROXY:"
        echo "   - registry.terraform.io"
        echo "   - releases.hashicorp.com"
    else
        echo "✅ registry.terraform.io уже в NO_PROXY"
    fi
else
    echo "ℹ️  Прокси не настроен"
fi

echo ""
echo "🔍 Проверка доступности Terraform registry..."

# Проверка доступности registry.terraform.io
if command -v curl &> /dev/null; then
    if curl -s -I --max-time 5 https://registry.terraform.io > /dev/null 2>&1; then
        echo "✅ registry.terraform.io доступен"
    else
        echo "❌ Ошибка: registry.terraform.io недоступен"
        echo "   Проверьте сетевое подключение или настройки прокси"
        exit 1
    fi
else
    echo "⚠️  curl не найден, пропускаем проверку доступности"
fi

echo ""
echo "✅ Окружение настроено!"
echo ""
echo "📝 Текущие настройки:"
echo "   NO_PROXY=$NO_PROXY"
echo ""
echo "🚀 Теперь можно запускать Terraform:"
echo "   source scripts/setup-terraform-env.sh"
echo "   terraform init"
echo ""
echo "💡 Для постоянного использования добавьте в ~/.bashrc или ~/.zshrc:"
echo '   export NO_PROXY="${NO_PROXY},registry.terraform.io,releases.hashicorp.com"'
