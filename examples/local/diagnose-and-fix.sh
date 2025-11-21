#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  DNS Server Diagnostic and Fix Script${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Function to check command execution
check_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        return 1
    fi
}

# 1. Check cloud-init status
echo -e "${YELLOW}[1/7]${NC} Checking cloud-init status..."
CLOUD_INIT_STATUS=$(cloud-init status 2>&1)
echo "$CLOUD_INIT_STATUS"
if echo "$CLOUD_INIT_STATUS" | grep -q "status: done"; then
    echo -e "${GREEN}✓ cloud-init has finished${NC}"
elif echo "$CLOUD_INIT_STATUS" | grep -q "status: running"; then
    echo -e "${YELLOW}⚠ cloud-init is still running. Please wait...${NC}"
    echo "You can monitor progress with: sudo tail -f /var/log/cloud-init-output.log"
    exit 0
else
    echo -e "${RED}✗ cloud-init status unknown${NC}"
fi
echo ""

# 2. Check if PowerDNS is installed
echo -e "${YELLOW}[2/7]${NC} Checking if PowerDNS is installed..."
if dpkg -l | grep -q pdns-server; then
    echo -e "${GREEN}✓ PowerDNS is installed${NC}"
    PDNS_VERSION=$(dpkg -l | grep pdns-server | awk '{print $3}')
    echo "  Version: $PDNS_VERSION"
else
    echo -e "${RED}✗ PowerDNS is not installed${NC}"
    echo "Installing PowerDNS..."
    sudo apt-get update
    sudo apt-get install -y pdns-server pdns-backend-sqlite3 sqlite3
fi
echo ""

# 3. Check PowerDNS service status
echo -e "${YELLOW}[3/7]${NC} Checking PowerDNS service status..."
if systemctl is-active --quiet pdns; then
    echo -e "${GREEN}✓ PowerDNS is running${NC}"
    systemctl status pdns --no-pager | head -n 10
else
    echo -e "${RED}✗ PowerDNS is not running${NC}"
    echo "Recent logs:"
    sudo journalctl -u pdns -n 20 --no-pager
fi
echo ""

# 4. Check PowerDNS configuration
echo -e "${YELLOW}[4/7]${NC} Checking PowerDNS configuration..."
if [ -f /etc/powerdns/pdns.conf ]; then
    echo -e "${GREEN}✓ Configuration file exists${NC}"
    echo "Configuration preview:"
    grep -v "^#" /etc/powerdns/pdns.conf | grep -v "^$" | head -n 15
else
    echo -e "${RED}✗ Configuration file missing${NC}"
fi
echo ""

# 5. Check PowerDNS database
echo -e "${YELLOW}[5/7]${NC} Checking PowerDNS database..."
DB_PATH="/var/lib/powerdns/pdns.sqlite3"
if [ -f "$DB_PATH" ]; then
    echo -e "${GREEN}✓ Database exists${NC}"
    echo "Database info:"
    ls -lh "$DB_PATH"

    # Check if zones exist
    ZONE_COUNT=$(sudo sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM domains;" 2>/dev/null)
    if [ -n "$ZONE_COUNT" ] && [ "$ZONE_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $ZONE_COUNT zone(s)${NC}"
        sudo sqlite3 "$DB_PATH" "SELECT name, type FROM domains;"
    else
        echo -e "${YELLOW}⚠ No zones found in database${NC}"
    fi
else
    echo -e "${RED}✗ Database does not exist${NC}"
fi
echo ""

# 6. Check port 53
echo -e "${YELLOW}[6/7]${NC} Checking if port 53 is listening..."
if sudo ss -tulpn | grep -q ":53 "; then
    echo -e "${GREEN}✓ Port 53 is listening${NC}"
    sudo ss -tulpn | grep ":53 "
else
    echo -e "${RED}✗ Port 53 is not listening${NC}"
fi
echo ""

# 7. Check firewall
echo -e "${YELLOW}[7/7]${NC} Checking firewall status..."
if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(sudo ufw status 2>&1)
    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        echo -e "${GREEN}✓ Firewall is active${NC}"
        echo "DNS ports status:"
        echo "$UFW_STATUS" | grep -E "(53|8081)"
    else
        echo -e "${YELLOW}⚠ Firewall is not active${NC}"
    fi
else
    echo -e "${YELLOW}⚠ UFW not installed${NC}"
fi
echo ""

# Summary and recommendations
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Summary and Recommendations${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if we need to fix anything
NEEDS_FIX=false

if ! systemctl is-active --quiet pdns; then
    echo -e "${YELLOW}⚠ PowerDNS is not running${NC}"
    NEEDS_FIX=true
fi

if [ ! -f "$DB_PATH" ]; then
    echo -e "${YELLOW}⚠ Database needs to be created${NC}"
    NEEDS_FIX=true
fi

if [ "$NEEDS_FIX" = true ]; then
    echo ""
    echo -e "${YELLOW}Would you like to run the setup script to fix these issues? [y/N]${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo ""
        echo -e "${BLUE}Running setup script...${NC}"

        # Check if setup script exists
        if [ -f /usr/local/bin/init-powerdns.sh ]; then
            sudo /usr/local/bin/init-powerdns.sh
            sudo systemctl restart pdns
            sleep 3

            # Test DNS
            echo ""
            echo -e "${BLUE}Testing DNS server...${NC}"
            if [ -f /usr/local/bin/test-dns.sh ]; then
                sudo /usr/local/bin/test-dns.sh
            fi
        else
            echo -e "${RED}✗ Setup script not found${NC}"
            echo "The cloud-init may not have completed successfully."
            echo "Check logs: sudo tail -100 /var/log/cloud-init-output.log"
        fi
    fi
else
    echo -e "${GREEN}✓ Everything looks good!${NC}"
    echo ""
    echo -e "${BLUE}Testing DNS server...${NC}"
    if [ -f /usr/local/bin/test-dns.sh ]; then
        sudo /usr/local/bin/test-dns.sh
    fi
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Additional Commands${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "View cloud-init logs:    ${YELLOW}sudo tail -f /var/log/cloud-init-output.log${NC}"
echo -e "View PowerDNS logs:      ${YELLOW}sudo journalctl -u pdns -f${NC}"
echo -e "Restart PowerDNS:        ${YELLOW}sudo systemctl restart pdns${NC}"
echo -e "Check DNS records:       ${YELLOW}dig @localhost test.local SOA${NC}"
echo -e "View TSIG info:          ${YELLOW}cat /root/tsig-info.txt${NC}"
echo ""
