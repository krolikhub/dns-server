#!/bin/bash

# Quick VM status checker for DNS server
# Run this from your host machine (not inside the VM)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  DNS Server VM Status Checker${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Get DNS IP from terraform
DNS_IP=$(terraform output -raw dns_server_ip 2>/dev/null)
if [ -z "$DNS_IP" ]; then
    echo -e "${RED}✗ Could not get DNS IP from terraform${NC}"
    echo "Make sure you've run 'terraform apply' first"
    exit 1
fi

echo -e "DNS Server IP: ${YELLOW}${DNS_IP}${NC}"
echo ""

# Check if VM is reachable
echo -e "${YELLOW}[1/4]${NC} Checking if VM is reachable (ping)..."
if ping -c 2 -W 3 ${DNS_IP} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ VM is reachable${NC}"
else
    echo -e "${RED}✗ VM is not reachable${NC}"
    echo "The VM may still be booting. Wait 30 seconds and try again."
    exit 1
fi
echo ""

# Check SSH
echo -e "${YELLOW}[2/4]${NC} Checking SSH access..."
if timeout 5 ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 ubuntu@${DNS_IP} "echo 'SSH OK'" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SSH is working${NC}"
else
    echo -e "${RED}✗ SSH is not working yet${NC}"
    echo "The VM is booting. Wait 30 seconds and try again."
    echo "You can also try: virsh console dns-server"
    exit 1
fi
echo ""

# Check cloud-init status
echo -e "${YELLOW}[3/4]${NC} Checking cloud-init status..."
CLOUD_INIT_STATUS=$(ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${DNS_IP} "cloud-init status 2>&1" 2>/dev/null)

if echo "$CLOUD_INIT_STATUS" | grep -q "status: done"; then
    echo -e "${GREEN}✓ cloud-init has finished${NC}"
    CLOUD_INIT_DONE=true
elif echo "$CLOUD_INIT_STATUS" | grep -q "status: running"; then
    echo -e "${YELLOW}⚠ cloud-init is still running${NC}"
    echo "This usually takes 2-4 minutes. Please wait..."
    echo ""
    echo "You can monitor progress with:"
    echo -e "  ${YELLOW}ssh -i ~/.ssh/id_ed25519 ubuntu@${DNS_IP} 'sudo tail -f /var/log/cloud-init-output.log'${NC}"
    CLOUD_INIT_DONE=false
else
    echo -e "${YELLOW}⚠ cloud-init status: $CLOUD_INIT_STATUS${NC}"
    CLOUD_INIT_DONE=false
fi
echo ""

# Check PowerDNS
echo -e "${YELLOW}[4/4]${NC} Checking PowerDNS status..."
PDNS_STATUS=$(ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${DNS_IP} "systemctl is-active pdns 2>&1" 2>/dev/null)

if [ "$PDNS_STATUS" = "active" ]; then
    echo -e "${GREEN}✓ PowerDNS is running${NC}"
    PDNS_RUNNING=true
else
    echo -e "${RED}✗ PowerDNS is not running${NC}"
    PDNS_RUNNING=false
fi
echo ""

# Summary
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$CLOUD_INIT_DONE" = true ] && [ "$PDNS_RUNNING" = true ]; then
    echo -e "${GREEN}✓ DNS Server is ready!${NC}"
    echo ""
    echo "You can now run the test script:"
    echo -e "  ${YELLOW}./test-dns-server.sh${NC}"
    echo ""
    echo "Or SSH into the server:"
    echo -e "  ${YELLOW}ssh -i ~/.ssh/id_ed25519 ubuntu@${DNS_IP}${NC}"
    exit 0
elif [ "$CLOUD_INIT_DONE" = false ]; then
    echo -e "${YELLOW}⚠ VM is still provisioning${NC}"
    echo ""
    echo "Please wait for cloud-init to complete (usually 2-4 minutes)."
    echo ""
    echo "Monitor progress:"
    echo -e "  ${YELLOW}ssh -i ~/.ssh/id_ed25519 ubuntu@${DNS_IP} 'sudo tail -f /var/log/cloud-init-output.log'${NC}"
    exit 1
else
    echo -e "${RED}✗ PowerDNS is not running${NC}"
    echo ""
    echo "Cloud-init has finished but PowerDNS isn't running."
    echo "Let's run the diagnostic script to find out why."
    echo ""

    # Offer to run diagnostic
    echo -e "${YELLOW}Would you like to run the diagnostic script on the VM? [Y/n]${NC}"
    read -r response
    response=${response:-Y}

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo ""
        echo -e "${BLUE}Copying diagnostic script to VM...${NC}"
        scp -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null diagnose-and-fix.sh ubuntu@${DNS_IP}:~/ 2>/dev/null

        echo -e "${BLUE}Running diagnostic script...${NC}"
        echo ""
        ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t ubuntu@${DNS_IP} "chmod +x diagnose-and-fix.sh && ./diagnose-and-fix.sh"

        echo ""
        echo -e "${BLUE}Checking PowerDNS status again...${NC}"
        PDNS_STATUS=$(ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${DNS_IP} "systemctl is-active pdns 2>&1" 2>/dev/null)

        if [ "$PDNS_STATUS" = "active" ]; then
            echo -e "${GREEN}✓ PowerDNS is now running!${NC}"
            echo ""
            echo "You can now run the test script:"
            echo -e "  ${YELLOW}./test-dns-server.sh${NC}"
        else
            echo -e "${RED}✗ PowerDNS is still not running${NC}"
            echo ""
            echo "Please check the logs on the VM:"
            echo -e "  ${YELLOW}ssh -i ~/.ssh/id_ed25519 ubuntu@${DNS_IP}${NC}"
            echo -e "  ${YELLOW}sudo journalctl -u pdns -n 50${NC}"
        fi
    else
        echo ""
        echo "To investigate manually, SSH into the VM:"
        echo -e "  ${YELLOW}ssh -i ~/.ssh/id_ed25519 ubuntu@${DNS_IP}${NC}"
        echo ""
        echo "Then check:"
        echo -e "  ${YELLOW}cloud-init status${NC}"
        echo -e "  ${YELLOW}sudo journalctl -u pdns${NC}"
        echo -e "  ${YELLOW}sudo systemctl status pdns${NC}"
    fi
    exit 1
fi
