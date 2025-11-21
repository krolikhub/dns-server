# Safe Destroy Order for DNS Server

This document explains the correct order for destroying DNS server resources to avoid common issues like "Directory not empty" errors.

## Problem

When using `terraform destroy` with the `-target` option or when Terraform encounters errors during destruction, resources may not be destroyed in the correct order. This can lead to:

- **Directory not empty** errors when trying to delete storage pools
- Orphaned volumes in libvirt
- Leftover network interfaces
- Resources stuck in Terraform state

## Solution: Proper Destruction Order

Resources must be destroyed in **reverse dependency order**:

### 1. Virtual Machine (Domain)
```bash
terraform destroy -target=module.dns_server.libvirt_domain.dns_server
```

The VM must be destroyed first because it depends on:
- Volumes (disks)
- Network interfaces
- Cloud-init disk

### 2. Cloud-init Disk
```bash
terraform destroy -target=module.dns_server.libvirt_cloudinit_disk.cloudinit
```

### 3. VM Disk (Main Volume)
```bash
terraform destroy -target=module.dns_server.libvirt_volume.dns_server
```

This volume depends on the base image.

### 4. Base Image (Base Volume)
```bash
terraform destroy -target=module.dns_server.libvirt_volume.base
```

### 5. Storage Pool
```bash
terraform destroy -target=module.dns_server.libvirt_pool.vm_pool
```

The pool can only be destroyed after all volumes are removed. If you get "Directory not empty" error here, see the troubleshooting section below.

### 6. Network
```bash
terraform destroy -target=module.dns_server.libvirt_network.dns_network
```

### 7. Remaining Resources
```bash
terraform destroy
```

Clean up any remaining resources (random passwords, data sources, etc.).

## Recommended Method: Use the Safe Destroy Script

Instead of manually running commands in order, use the provided script:

```bash
cd examples/local
../../scripts/safe-destroy.sh
```

This script:
- ✅ Shows all resources that will be destroyed
- ✅ Asks for confirmation (type 'yes')
- ✅ Destroys resources in the correct order
- ✅ Handles errors gracefully
- ✅ Provides clear progress feedback
- ✅ Verifies cleanup completion

### Non-interactive mode:
```bash
../../scripts/safe-destroy.sh --yes
```

## Dependency Graph

```
libvirt_domain (VM)
    ├── libvirt_cloudinit_disk
    │   └── libvirt_pool
    ├── libvirt_volume (main disk)
    │   ├── libvirt_volume (base image)
    │   │   └── libvirt_pool
    │   └── libvirt_pool
    └── libvirt_network
```

## Troubleshooting

### Error: Directory not empty

```
Error: error deleting storage pool: failed to remove pool
'/var/lib/libvirt/pools/dns-server': Directory not empty
```

**Cause:** Storage pool directory still contains files (volumes, orphaned files, or files not managed by Terraform).

**Solution:**

```bash
# 1. Run cleanup script
sudo ./scripts/cleanup-storage-pool.sh

# 2. Remove pool from Terraform state
cd examples/local
terraform state rm module.dns_server.libvirt_pool.vm_pool

# 3. Complete destroy
terraform destroy
```

### Error: Resource busy

```
Error: error destroying libvirt volume: Storage volume not found
```

**Cause:** VM is still running or volumes are still attached.

**Solution:**

```bash
# 1. Force stop VM
virsh destroy dns-server 2>/dev/null || true
virsh undefine dns-server 2>/dev/null || true

# 2. Retry destroy
terraform destroy
```

### Error: Network is active

```
Error: error destroying libvirt network: Network is active
```

**Cause:** Network interface is still in use by a VM.

**Solution:**

```bash
# 1. Ensure VM is destroyed first
terraform destroy -target=module.dns_server.libvirt_domain.dns_server

# 2. Destroy network
terraform destroy -target=module.dns_server.libvirt_network.dns_network
```

## Manual Cleanup (Last Resort)

If Terraform cannot destroy resources, clean up manually:

```bash
# 1. Stop and remove VM
virsh destroy dns-server 2>/dev/null || true
virsh undefine dns-server 2>/dev/null || true

# 2. Remove volumes
virsh vol-list dns-server-pool 2>/dev/null | tail -n +3 | awk '{print $1}' | while read vol; do
  [ -n "$vol" ] && virsh vol-delete "$vol" --pool dns-server-pool
done

# 3. Destroy and undefine pool
virsh pool-destroy dns-server-pool 2>/dev/null || true
virsh pool-undefine dns-server-pool 2>/dev/null || true

# 4. Remove files manually (if needed)
sudo rm -rf /var/lib/libvirt/pools/dns-server/*
sudo rmdir /var/lib/libvirt/pools/dns-server

# 5. Destroy network
virsh net-destroy dns-server-network 2>/dev/null || true
virsh net-undefine dns-server-network 2>/dev/null || true

# 6. Clean Terraform state
cd examples/local
terraform state rm module.dns_server.libvirt_domain.dns_server
terraform state rm module.dns_server.libvirt_cloudinit_disk.cloudinit
terraform state rm module.dns_server.libvirt_volume.dns_server
terraform state rm module.dns_server.libvirt_volume.base
terraform state rm module.dns_server.libvirt_pool.vm_pool
terraform state rm module.dns_server.libvirt_network.dns_network

# 7. Final cleanup
terraform destroy
```

## Prevention

To avoid destroy issues:

1. **Always use the safe destroy script**
   ```bash
   ../../scripts/safe-destroy.sh
   ```

2. **Never use `-target` with destroy unless necessary**
   - Targeted destroys can break dependency order
   - Only use when recovering from errors

3. **Ensure VM is stopped before destroying storage**
   - Terraform should handle this, but manual intervention may be needed

4. **Check for running VMs before destroy**
   ```bash
   virsh list --all | grep dns-server
   ```

5. **Backup important data before destroying**
   - DNS zone data
   - TSIG keys (from Terraform outputs)
   - PowerDNS API keys

## Quick Reference

| Command | Purpose |
|---------|---------|
| `../../scripts/safe-destroy.sh` | Recommended: Safe destroy with confirmation |
| `../../scripts/safe-destroy.sh --yes` | Non-interactive safe destroy |
| `sudo ../../scripts/cleanup-storage-pool.sh` | Clean up storage pool manually |
| `terraform destroy -target=<resource>` | Destroy specific resource |
| `terraform state rm <resource>` | Remove resource from state |
| `virsh list --all` | List all VMs |
| `virsh pool-list --all` | List all storage pools |
| `virsh net-list --all` | List all networks |

## See Also

- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - General troubleshooting guide
- [README.md](../README.md) - Project overview and quick start
- [scripts/cleanup-storage-pool.sh](../scripts/cleanup-storage-pool.sh) - Storage pool cleanup script
- [scripts/safe-destroy.sh](../scripts/safe-destroy.sh) - Safe destroy script
