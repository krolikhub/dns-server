#!/bin/bash
# Скрипт для тестирования динамического обновления DNS через nsupdate

set -e

# Параметры (можно переопределить через переменные окружения)
DNS_SERVER=${DNS_SERVER:-"192.168.122.100"}
DNS_ZONE=${DNS_ZONE:-"test.local"}
TSIG_KEY_NAME=${TSIG_KEY_NAME:-"txt-updater"}
TSIG_SECRET=${TSIG_SECRET:-""}
TSIG_ALGORITHM=${TSIG_ALGORITHM:-"hmac-sha256"}

if [ -z "$TSIG_SECRET" ]; then
    echo "Ошибка: TSIG_SECRET не установлен!"
    echo "Использование:"
    echo "  TSIG_SECRET=\$(terraform output -raw tsig_secret) $0"
    exit 1
fi

echo "=== Тестирование DNS Update ==="
echo "DNS Server: $DNS_SERVER"
echo "DNS Zone: $DNS_ZONE"
echo "TSIG Key: $TSIG_KEY_NAME"
echo ""

# Создание временного файла с TSIG ключом
TSIG_FILE=$(mktemp)
trap "rm -f $TSIG_FILE" EXIT

cat > "$TSIG_FILE" <<EOF
key "$TSIG_KEY_NAME" {
  algorithm $TSIG_ALGORITHM;
  secret "$TSIG_SECRET";
};
EOF

echo "1. Добавление TXT записи..."
TEST_RECORD="_acme-challenge.${DNS_ZONE}"
TEST_VALUE="test-txt-$(date +%s)"

nsupdate -k "$TSIG_FILE" <<EOF
server $DNS_SERVER
zone $DNS_ZONE
update add $TEST_RECORD 300 IN TXT "$TEST_VALUE"
send
EOF

echo "   ✓ Запись добавлена"
echo ""

sleep 2

echo "2. Проверка записи..."
RESULT=$(dig @$DNS_SERVER $TEST_RECORD TXT +short)
if [ -n "$RESULT" ]; then
    echo "   ✓ Запись найдена: $RESULT"
else
    echo "   ✗ Запись НЕ найдена!"
    exit 1
fi
echo ""

echo "3. Удаление записи..."
nsupdate -k "$TSIG_FILE" <<EOF
server $DNS_SERVER
zone $DNS_ZONE
update delete $TEST_RECORD TXT
send
EOF

echo "   ✓ Запись удалена"
echo ""

sleep 2

echo "4. Проверка удаления..."
RESULT=$(dig @$DNS_SERVER $TEST_RECORD TXT +short)
if [ -z "$RESULT" ]; then
    echo "   ✓ Запись успешно удалена"
else
    echo "   ✗ Запись всё ещё существует: $RESULT"
    exit 1
fi
echo ""

echo "=== Все тесты пройдены успешно! ==="
