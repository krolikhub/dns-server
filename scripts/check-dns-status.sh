#!/bin/bash
# Скрипт для проверки статуса DNS сервера

DNS_SERVER=${DNS_SERVER:-"192.168.122.100"}
DNS_ZONE=${DNS_ZONE:-"test.local"}

echo "=== Проверка DNS Сервера ==="
echo "Server: $DNS_SERVER"
echo "Zone: $DNS_ZONE"
echo ""

echo "1. Проверка доступности порта 53 (UDP)..."
if nc -zuv -w 2 $DNS_SERVER 53 2>&1 | grep -q succeeded; then
    echo "   ✓ Порт 53 UDP доступен"
else
    echo "   ✗ Порт 53 UDP недоступен!"
fi
echo ""

echo "2. Проверка доступности порта 53 (TCP)..."
if nc -zv -w 2 $DNS_SERVER 53 2>&1 | grep -q succeeded; then
    echo "   ✓ Порт 53 TCP доступен"
else
    echo "   ✗ Порт 53 TCP недоступен!"
fi
echo ""

echo "3. SOA запись зоны $DNS_ZONE:"
dig @$DNS_SERVER $DNS_ZONE SOA +short
echo ""

echo "4. NS записи зоны $DNS_ZONE:"
dig @$DNS_SERVER $DNS_ZONE NS +short
echo ""

echo "5. Проверка PowerDNS API (порт 8081)..."
if curl -s -o /dev/null -w "%{http_code}" http://$DNS_SERVER:8081 | grep -q 200; then
    echo "   ✓ PowerDNS API доступен"
else
    echo "   ⚠ PowerDNS API может быть недоступен или требует авторизацию"
fi
echo ""

echo "6. Информация о VM:"
virsh dominfo dns-server 2>/dev/null || echo "   ⚠ VM информация недоступна (требуется libvirt)"
echo ""

echo "7. IP адрес VM:"
virsh domifaddr dns-server 2>/dev/null || echo "   ⚠ IP адрес недоступен (требуется libvirt)"
