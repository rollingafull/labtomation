# Idempotence in Labtomation

## What is Idempotence?

Idempotence means you can run the script multiple times with the same parameters and get the same result without errors or duplicates. The script detects what is already configured and only makes necessary changes.

## Operation Modes

### 1. Idempotent Mode (Default)

If the VM already exists, the script:
- ✅ Detects the current VM state
- ✅ Completes only missing configurations
- ✅ Skips already completed steps
- ✅ Does not fail if the VM exists

**Example:**
```bash
./labtomation.sh --vmid 100 --os rocky10

# If you run it again with the same VMID:
./labtomation.sh --vmid 100 --os rocky10
# ✅ Script detects VM 100 exists and completes only what's needed
```

### 2. Force Mode (--force)

If you want to destroy and recreate the VM from scratch:
- ⚠️ Stops the VM if it's running
- ⚠️ Destroys the existing VM
- ✅ Creates a new VM from scratch

**Example:**
```bash
./labtomation.sh --vmid 100 --os rocky10 --force
# ⚠️ Will destroy existing VM 100 and recreate it
```

### 3. Auto-VMID Mode (Without specifying --vmid)

Always generates a new available VMID, so there are never conflicts:

**Example:**
```bash
./labtomation.sh --os rocky10
# First execution: creates VM 100
./labtomation.sh --os rocky10
# Second execution: creates VM 101 (new automatic VMID)
```

## Idempotent Checks by Component

### ✅ VM Creation (`create_vm`)

**Behavior:**
- If VM exists and is complete → SKIP (no changes)
- If VM exists but incomplete → CONTINUES configuration
- If `--force` is active → DESTROYS and RECREATES

**Checks:**
- EFI disk configured
- SCSI0 disk present
- Cloud-init drive
- Boot order configured
- QEMU guest agent enabled

### ✅ Disk Import (`import_disk`)

**Behavior:**
- If `scsi0` already exists → SKIP
- If size differs → INFORMS (does not auto-resize)
- If doesn't exist → IMPORTS image and RESIZES to requested size

**Example output:**
```
✓ Disk already attached to VM 100, skipping import
ℹ Current disk size (32G) differs from requested (64G)
ℹ To resize, use: qm resize 100 scsi0 64G
```

**Note:** As of v1.0.0, new VMs properly resize disks using `qm disk resize`.

### ✅ Boot Configuration (`configure_vm_boot`)

**Behavior:**
- Cloud-init drive: checks if `ide2:cloudinit` exists
- Boot order: checks if `boot:order=scsi0` is configured
- QEMU agent: checks if `agent:enabled=1` is configured

**Each component is verified independently.**

### ✅ Cloud-Init (`configure_cloud_init`)

**Behavior:**
- User: compares current user with requested
- SSH keys: always updates (safe to do)
- DHCP network: checks if already configured
- Upgrade flag: always updates (idempotent)

### ✅ Image Download

**Behavior:**
```bash
if [ ! -f "$os_file" ]; then
    # Download image
else
    # Reuse existing image
fi
```

### ✅ SSH Keys

**Behavior:**
```bash
if [ -f "${ssh_key}.pub" ] && [ -f "$ssh_key" ]; then
    # Reuse existing keys
else
    # Generate new keys
fi
```

## Use Cases

### Case 1: Complete Partially Created VM

If the script failed halfway:

```bash
# First execution (failed after creating VM but before cloud-init)
./labtomation.sh --vmid 100 --os rocky10
# ERROR: lost network connection

# Second execution (completes what was missing)
./labtomation.sh --vmid 100 --os rocky10
# ✅ Detects existing VM 100
# ✅ Detects missing cloud-init
# ✅ Completes the configuration
```

### Case 2: Change Existing Configuration

To change the configuration of an existing VM:

```bash
# Original VM with 2 cores
./labtomation.sh --vmid 100 --cores 2

# You want to recreate it with 4 cores
./labtomation.sh --vmid 100 --cores 4 --force
# ⚠️ Destroys and recreates with 4 cores
```

### Case 3: Re-run After Temporary Error

If there was a temporary error (network, storage):

```bash
./labtomation.sh --vmid 100 --os debian13
# ERROR: timeout downloading image

# Run again after resolving the issue
./labtomation.sh --vmid 100 --os debian13
# ✅ Reuses already completed work
# ✅ Retries the download
```

## Utility Functions

### `get_vm_state <vmid>`

Returns JSON with current VM state:

```bash
get_vm_state 100
```

**Output:**
```json
{
    "exists": true,
    "vmid": 100,
    "name": "labtomation",
    "has_efidisk": 1,
    "has_scsi0": 1,
    "has_cloudinit": 1,
    "has_boot_config": 1,
    "has_agent": 1,
    "is_complete": 1
}
```

### `validate_vmid <vmid>`

Checks if a VMID is available:

```bash
if validate_vmid 100; then
    echo "VMID 100 is available"
else
    echo "VMID 100 already exists"
fi
```

### `set_vm_tags <vmid> <tags>`

Sets tags on a VM (idempotent):

```bash
# Set multiple tags
set_vm_tags 100 "rocky10;production;webserver"

# Tags are automatically formatted with semicolons
```

### `add_vm_tag <vmid> <tag>`

Adds a tag without removing existing ones (idempotent):

```bash
# Add service tag
add_vm_tag 100 "ansible"

# Add another tag
add_vm_tag 100 "terraform"

# If tag already exists, it's skipped (SKIP)
```

## Environment Variables

### `VM_FORCE_RECREATE`

```bash
# Force recreation programmatically
export VM_FORCE_RECREATE=1
./labtomation.sh --vmid 100
```

## Automatic Tags on VMs

All created VMs have **automatic tags** for easy identification:

### Assigned Tags

1. **Operating System Tag** (during creation):
   - `rocky10` - Rocky Linux 10
   - `debian13` - Debian 13
   - `ubuntu2404` - Ubuntu 24.04

2. **Service Tags** (after installation):
   - `ansible` - Ansible is installed
   - `terraform` - Terraform is installed
   - `vault` - HashiCorp Vault is installed
   - `jenkins` - Jenkins CI/CD is installed

### Tag Examples

A VM created with Ubuntu 24.04 will have:

```text
Tags: ubuntu2404;ansible;terraform;vault;jenkins
```

### View VM Tags

```bash
# View complete configuration
qm config 100 | grep tags

# View only tags
pvesh get /cluster/resources --type vm --output-format json | jq '.[] | select(.vmid == 100) | {vmid, name, tags}'
```

### Filter VMs by Tags in Proxmox UI

Tags appear in the Proxmox web interface:
- "Tags" column in VM list
- Tag filters available
- Automatic colors for visual differentiation

**Benefits:**
- Quickly identify which services are installed
- Filter VMs by capability (e.g., all VMs with Terraform)
- Organize lab environment by function
- Inventory management

## Advantages of Idempotence

✅ **Error recovery**: If something fails, just re-run the script

✅ **Safe testing**: You can test the script multiple times

✅ **CI/CD friendly**: Ideal for automated pipelines

✅ **No manual cleanup**: No need for `qm destroy` before each test

✅ **Incremental configuration**: Completes partially configured VMs

✅ **Automatic tags**: Identify VMs by OS and services easily

## Limitations

⚠️ **Does not update existing configurations** (unless you use `--force`)
- If you change cores, memory, etc., you need `--force` to recreate
- Already applied configurations are not modified

⚠️ **Does not automatically resize disks** (on existing VMs)
- If disk exists, reports differences but doesn't resize
- You must use `qm resize` manually
- New VMs in v1.0.0+ properly resize disks during creation

⚠️ **Cloud-init runs only on first boot**
- If VM already booted, cloud-init won't re-run
- SSH key changes require `--force` to apply on running VM

## Best Practices

1. **Use auto-VMID for testing**:
   ```bash
   ./labtomation.sh --os rocky10  # Generates automatic VMID
   ```

2. **Use --force only when necessary**:
   ```bash
   # Only if you need to change base configuration
   ./labtomation.sh --vmid 100 --cores 4 --force
   ```

3. **Check state before forcing**:
   ```bash
   qm config 100  # View current configuration
   # If it meets your needs, don't use --force
   ```

4. **Informative logs**:
   - Pay attention to `SKIP` vs `INFO` vs `SUCCESS` messages
   - `SKIP` = already configured
   - `INFO` = configuring now
   - `SUCCESS` = configuration successful

## Troubleshooting

### "VMID already exists"

```bash
# Option 1: Let it continue idempotently
./labtomation.sh --vmid 100 --os rocky10

# Option 2: Force recreation
./labtomation.sh --vmid 100 --os rocky10 --force

# Option 3: Use auto-VMID
./labtomation.sh --os rocky10  # Without specifying --vmid
```

### "VM exists but is incomplete"

The script will continue and complete what's missing automatically.

### "Disk already attached, skipping import"

This is normal and correct - the disk is already configured.

### "Current disk size differs from requested"

On existing VMs, you need to manually resize:
```bash
qm disk resize 100 scsi0 +32G  # Add 32GB
# or
qm disk resize 100 scsi0 64G   # Set to 64GB total
```

New VMs created with v1.0.0+ automatically resize to the requested size.

## Idempotence Testing

```bash
# Test 1: Running twice should be safe
./labtomation.sh --vmid 100 --os rocky10
./labtomation.sh --vmid 100 --os rocky10  # Should SKIP everything

# Test 2: Interrupt and continue
./labtomation.sh --vmid 101 --os debian13
# Ctrl+C after creating VM
./labtomation.sh --vmid 101 --os debian13  # Should continue

# Test 3: Force recreate
./labtomation.sh --vmid 102 --os ubuntu2404
./labtomation.sh --vmid 102 --os ubuntu2404 --force  # Should recreate
```

## Implementation Details

### VM State Detection

The `get_vm_state()` function performs comprehensive checks:

```bash
# Checks performed:
- VM existence (qm status)
- EFI disk presence (efidisk0)
- Main disk presence (scsi0)
- Cloud-init drive (ide2)
- Boot order configuration
- QEMU agent configuration
```

### Tag Management

Tags are managed idempotently:

```bash
# Adding tags:
1. Read current tags
2. Check if tag already exists
3. If exists → SKIP
4. If not → Add to tag list
5. Update VM configuration
```

### Force Recreation Flow

When `--force` is used:

```bash
1. Check if VM exists
2. If running → Stop VM (qm stop)
3. Destroy VM (qm destroy)
4. Wait for destruction to complete
5. Create new VM from scratch
6. All configurations applied fresh
```

## Compatibility

### Operating Systems

✅ **Rocky Linux 10**
- Full idempotence support
- Automatic ansible-core installation
- RHEL 9 repository for HashiCorp tools

✅ **Debian 13 (Trixie)**
- Modern GPG key handling
- All tools install idempotently
- Cloud-init support verified

✅ **Ubuntu 24.04 LTS (Noble)**
- Complete compatibility
- Same features as Debian 13
- Tested and verified

### Proxmox Versions

- Proxmox VE 7.0+ (Q35 + EFI support required)
- Proxmox VE 8.0+ (recommended)
- Clustered and standalone setups supported

## Version History

### v1.0.0 (2025-10-23) - First Stable Release 🎉
- ✅ Production-ready idempotence across all operations
- ✅ Fixed disk resize (proper `qm disk resize` implementation)
- ✅ Service-based tagging system (OS + tools)
- ✅ Modern GPG key handling for Debian/Ubuntu
- ✅ FHS-compliant paths (/opt/labtomation/)
- ✅ Comprehensive state checking and validation
- ✅ Safe re-run capabilities without side effects

## Additional Resources

- **[setup/README.md](README.md)** - Main documentation
- **[../README.md](../README.md)** - Project overview
- **[playbooks/README.md](playbooks/README.md)** - Ansible playbooks

## Summary

Idempotence in Labtomation ensures:

✅ **Reliability** - Safe to run multiple times
✅ **Recovery** - Auto-resume from failures
✅ **Testing** - No cleanup needed between runs
✅ **Flexibility** - Force recreation when needed
✅ **Visibility** - Automatic service tags
✅ **Compatibility** - Works on all supported OS

The idempotent design makes Labtomation suitable for both manual and automated deployments, ensuring consistent results regardless of execution count.
