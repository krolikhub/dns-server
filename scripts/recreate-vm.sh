#!/bin/bash
#
# Скрипт для пересоздания VM с исправленной SSH конфигурацией
#

set -e

EXAMPLE_DIR="/home/user/dns-server/examples/local"

echo "=========================================="
echo "Recreating VM with fixed SSH config"
echo "=========================================="
echo ""

cd "$EXAMPLE_DIR"

echo "[1/3] Destroying existing VM..."
terraform destroy -auto-approve
echo "✓ VM destroyed"
echo ""

echo "[2/3] Creating new VM with fixed SSH configuration..."
terraform apply -auto-approve
echo "✓ VM created"
echo ""

echo "[3/3] Waiting for VM to initialize (60 seconds)..."
sleep 60
echo "✓ VM should be ready"
echo ""

echo "=========================================="
echo "VM recreated successfully!"
echo "=========================================="
echo ""
echo "Default credentials:"
echo "  Username: ubuntu"
echo "  Password: ubuntu"
echo ""
echo "Try connecting:"
echo "  ssh ubuntu@192.168.200.100"
echo ""
echo "If prompted for password, enter: ubuntu"
echo ""
