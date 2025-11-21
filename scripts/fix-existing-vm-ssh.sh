#!/bin/bash
#
# Скрипт для исправления SSH на существующей VM через SSH ключ
#

set -e

VM_IP="192.168.200.100"
SSH_KEY="$HOME/.ssh/id_rsa"

echo "=========================================="
echo "Fixing SSH on existing VM"
echo "=========================================="
echo ""

# Проверяем наличие SSH ключа
if [ ! -f "$SSH_KEY" ]; then
    echo "ERROR: SSH key not found at $SSH_KEY"
    echo "Please specify your SSH key location."
    exit 1
fi

echo "[1/4] Testing SSH connection with key..."
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$VM_IP "echo 'SSH key works!'" 2>/dev/null; then
    echo "✓ SSH key authentication works!"
else
    echo "✗ Cannot connect with SSH key"
    echo ""
    echo "Options:"
    echo "1. Try with different user (root):"
    echo "   ssh -i $SSH_KEY root@$VM_IP"
    echo ""
    echo "2. Use Variant 3 (virsh console) from docs/SSH_PASSWORD_AUTH_FIX.md"
    echo ""
    echo "3. Recreate VM (recommended): ./scripts/recreate-vm.sh"
    exit 1
fi
echo ""

echo "[2/4] Copying fix script to VM..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    /home/user/dns-server/scripts/fix-ssh-password-auth.sh \
    ubuntu@$VM_IP:/tmp/
echo "✓ Script copied"
echo ""

echo "[3/4] Running fix script on VM..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$VM_IP \
    "sudo bash /tmp/fix-ssh-password-auth.sh"
echo ""

echo "[4/4] Testing password authentication..."
echo "Waiting 5 seconds for SSH to restart..."
sleep 5

echo ""
echo "=========================================="
echo "Fix applied! Now try connecting with password:"
echo "=========================================="
echo ""
echo "  ssh ubuntu@$VM_IP"
echo ""
echo "Default password: ubuntu"
echo ""
