#!/bin/bash
# Скрипт для получения информации о TSIG ключе из terraform

set -e

cd "$(dirname "$0")/../examples/local"

echo "=== TSIG Информация ==="
echo ""

echo "TSIG Key Name:"
terraform output tsig_key_name
echo ""

echo "TSIG Secret (base64):"
terraform output -raw tsig_secret
echo ""
echo ""

echo "=== Файл конфигурации для nsupdate ==="
echo ""
echo "Создать файл /tmp/tsig.key:"
echo ""

TSIG_NAME=$(terraform output -raw tsig_key_name)
TSIG_SECRET=$(terraform output -raw tsig_secret)

cat <<EOF
cat > /tmp/tsig.key <<'TSIGEOF'
key "$TSIG_NAME" {
  algorithm hmac-sha256;
  secret "$TSIG_SECRET";
};
TSIGEOF
EOF

echo ""
echo "=== Пример использования nsupdate ==="
echo ""
terraform output -raw nsupdate_example
