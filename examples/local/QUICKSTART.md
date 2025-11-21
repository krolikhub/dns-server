# Quick Start Guide - Local DNS Server

This guide will help you quickly set up and troubleshoot the local DNS server example.

## Prerequisites

1. **Install dependencies:**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils xsltproc

# Start libvirt
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Add your user to libvirt group
sudo usermod -a -G libvirt $(whoami)
newgrp libvirt
```

2. **Install Terraform:**
```bash
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

3. **Ensure you have an SSH key:**
```bash
# Check if you have an SSH key
ls -la ~/.ssh/id_ed25519.pub

# If not, create one
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

## Quick Setup

1. **Navigate to the example directory:**
```bash
cd examples/local
```

2. **Initialize and apply Terraform:**
```bash
terraform init
terraform apply -auto-approve
```

3. **Wait for the VM to provision** (this takes 2-5 minutes)
   - The VM needs to download packages and configure PowerDNS
   - Cloud-init runs in the background

4. **Run the test script:**
```bash
./test-dns-server.sh
```

## Troubleshooting

If the tests fail with "connection refused" or SSH errors, the VM is still provisioning.

### Check VM Status

```bash
# Ping the VM
ping -c 2 192.168.200.100

# SSH into the VM
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.200.100
```

### Run Diagnostic Script

Once you're SSHed into the VM, run the diagnostic script:

```bash
# Copy the diagnostic script to the VM
scp -i ~/.ssh/id_ed25519 diagnose-and-fix.sh ubuntu@192.168.200.100:~/

# SSH into the VM
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.200.100

# Run the diagnostic
chmod +x diagnose-and-fix.sh
./diagnose-and-fix.sh
```

The script will:
- Check if cloud-init has finished
- Verify PowerDNS installation and status
- Check database and configuration
- Offer to fix any issues automatically

### Common Issues

#### 1. Cloud-init still running

If cloud-init is still running, wait for it to complete:

```bash
# Check status
cloud-init status

# Watch the logs
sudo tail -f /var/log/cloud-init-output.log
```

#### 2. PowerDNS not running

If PowerDNS isn't running after cloud-init completes:

```bash
# Check logs
sudo journalctl -u pdns -n 50

# Try to start manually
sudo systemctl restart pdns
sudo systemctl status pdns
```

#### 3. Database issues

If the database wasn't created:

```bash
# Run the init script manually
sudo /usr/local/bin/init-powerdns.sh

# Restart PowerDNS
sudo systemctl restart pdns
```

### Manual Testing

Once PowerDNS is running, test it manually:

```bash
# From your host machine
dig @192.168.200.100 test.local SOA
dig @192.168.200.100 test.local NS

# Test TSIG updates
TSIG_SECRET=$(terraform output -raw tsig_secret)
echo $TSIG_SECRET

# Create TSIG key file
cat > /tmp/tsig.key <<EOF
key "txt-updater" {
  algorithm hmac-sha256;
  secret "$TSIG_SECRET";
};
EOF

# Add a test record
nsupdate -k /tmp/tsig.key <<EOF
server 192.168.200.100
zone test.local
update add test.test.local. 300 IN TXT "test123"
send
EOF

# Verify the record
dig @192.168.200.100 test.test.local TXT +short
```

## Expected Timeline

- **Terraform apply**: 30-60 seconds (downloads and creates VM)
- **Cloud-init**: 2-4 minutes (installs packages, configures services)
- **Total time**: 3-5 minutes from start to fully functional DNS server

## Useful Commands

```bash
# View all VMs
virsh list --all

# Connect to VM console
virsh console dns-server

# Check VM IP
virsh domifaddr dns-server

# View Terraform outputs
terraform output

# Get TSIG secret
terraform output -raw tsig_secret

# Destroy everything
terraform destroy
```

## Next Steps

Once everything is working:

1. Try adding DNS records via nsupdate
2. Experiment with the PowerDNS API (see main README.md)
3. Test from external machines
4. Configure WireGuard if needed (see main README.md)

## Getting Help

- Full documentation: [README.md](README.md)
- Troubleshooting: [../../TROUBLESHOOTING.md](../../TROUBLESHOOTING.md)
- Security: [../../SECURITY.md](../../SECURITY.md)
