#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Получаем переменные из Terraform
DNS_IP=$(terraform output -raw dns_server_ip 2>/dev/null)
DNS_ZONE=$(terraform output -raw dns_zone 2>/dev/null)
TSIG_SECRET=$(terraform output -raw tsig_secret 2>/dev/null)
TSIG_KEY_NAME=$(terraform output -raw tsig_key_name 2>/dev/null)
API_URL=$(terraform output -raw pdns_api_url 2>/dev/null)

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Проверка DNS сервера PowerDNS${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "DNS IP:   ${YELLOW}${DNS_IP}${NC}"
echo -e "DNS Zone: ${YELLOW}${DNS_ZONE}${NC}"
echo -e "API URL:  ${YELLOW}${API_URL}${NC}"
echo ""

# Счетчик успешных/неуспешных тестов
PASSED=0
FAILED=0

# Функция для проверки
check_test() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED++))
    fi
    echo ""
}

# 1. Проверка доступности сервера (ping)
echo -e "${YELLOW}[1/6]${NC} Проверка доступности сервера (ping)..."
ping -c 2 -W 3 ${DNS_IP} > /dev/null 2>&1
check_test $?

# 2. Проверка SSH доступа
echo -e "${YELLOW}[2/6]${NC} Проверка SSH доступа..."
timeout 5 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 ubuntu@${DNS_IP} "echo 'SSH OK'" > /dev/null 2>&1
check_test $?

# 3. Проверка DNS - SOA запись
echo -e "${YELLOW}[3/6]${NC} Проверка DNS - SOA запись зоны ${DNS_ZONE}..."
SOA_OUTPUT=$(dig @${DNS_IP} ${DNS_ZONE} SOA +short)
if [ -n "$SOA_OUTPUT" ]; then
    echo -e "  ${GREEN}SOA:${NC} $SOA_OUTPUT"
    check_test 0
else
    echo -e "  ${RED}SOA запись не найдена${NC}"
    check_test 1
fi

# 4. Проверка DNS - NS запись
echo -e "${YELLOW}[4/6]${NC} Проверка DNS - NS запись..."
NS_OUTPUT=$(dig @${DNS_IP} ${DNS_ZONE} NS +short)
if [ -n "$NS_OUTPUT" ]; then
    echo -e "  ${GREEN}NS:${NC} $NS_OUTPUT"
    check_test 0
else
    echo -e "  ${RED}NS запись не найдена${NC}"
    check_test 1
fi

# 5. Проверка PowerDNS API
echo -e "${YELLOW}[5/6]${NC} Проверка PowerDNS API..."
API_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/api_response.json "${API_URL}/api/v1/servers/localhost/zones/${DNS_ZONE}" 2>/dev/null)
if [ "$API_RESPONSE" = "200" ]; then
    echo -e "  ${GREEN}API доступен, зона найдена${NC}"
    check_test 0
else
    echo -e "  ${RED}API недоступен или зона не найдена (HTTP: $API_RESPONSE)${NC}"
    check_test 1
fi

# 6. Проверка динамического обновления через nsupdate (TSIG)
echo -e "${YELLOW}[6/6]${NC} Проверка динамического обновления DNS (TSIG)..."

# Создаем временный файл с TSIG ключом
TSIG_FILE=$(mktemp)
cat > "$TSIG_FILE" <<EOF
key "${TSIG_KEY_NAME}" {
  algorithm hmac-sha256;
  secret "${TSIG_SECRET}";
};
EOF

# Генерируем случайное значение для теста
TEST_VALUE="test-$(date +%s)"
TEST_RECORD="_acme-challenge.${DNS_ZONE}"

# Пытаемся обновить TXT запись
nsupdate -k "$TSIG_FILE" <<EOF > /dev/null 2>&1
server ${DNS_IP}
zone ${DNS_ZONE}
update delete ${TEST_RECORD} TXT
update add ${TEST_RECORD} 60 IN TXT "${TEST_VALUE}"
send
EOF

if [ $? -eq 0 ]; then
    # Ждем немного для применения изменений
    sleep 2

    # Проверяем, что запись действительно добавилась
    VERIFY=$(dig @${DNS_IP} ${TEST_RECORD} TXT +short | tr -d '"')
    if [ "$VERIFY" = "$TEST_VALUE" ]; then
        echo -e "  ${GREEN}Динамическое обновление работает${NC}"
        echo -e "  Добавлена запись: ${TEST_RECORD} = ${TEST_VALUE}"
        check_test 0
    else
        echo -e "  ${RED}Запись не обновилась (ожидалось: ${TEST_VALUE}, получено: ${VERIFY})${NC}"
        check_test 1
    fi
else
    echo -e "  ${RED}Ошибка nsupdate${NC}"
    check_test 1
fi

# Удаляем временный файл
rm -f "$TSIG_FILE"

# Итоговая статистика
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Результаты тестирования${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Успешно:   ${GREEN}${PASSED}${NC}"
echo -e "Провалено: ${RED}${FAILED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Все проверки пройдены успешно!${NC}"
    echo ""
    echo -e "${BLUE}Дополнительные команды:${NC}"
    echo -e "  • SSH доступ:    ${YELLOW}ssh -o StrictHostKeyChecking=no ubuntu@${DNS_IP}${NC}"
    echo -e "  • DNS запрос:    ${YELLOW}dig @${DNS_IP} ${DNS_ZONE} SOA${NC}"
    echo -e "  • Virsh console: ${YELLOW}virsh console dns-server${NC}"
    exit 0
else
    echo -e "${RED}✗ Некоторые проверки провалились${NC}"
    echo ""
    echo -e "${YELLOW}Рекомендации по отладке:${NC}"
    echo -e "  1. Проверьте логи VM:  ${YELLOW}virsh console dns-server${NC}"
    echo -e "  2. Проверьте SSH:      ${YELLOW}ssh ubuntu@${DNS_IP}${NC}"
    echo -e "  3. Проверьте сервисы:  ${YELLOW}ssh ubuntu@${DNS_IP} 'systemctl status pdns'${NC}"
    exit 1
fi
