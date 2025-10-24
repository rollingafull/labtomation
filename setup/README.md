# Labtomation Setup Scripts

Automated setup scripts for creating DevOps lab environments on Proxmox VE.

## Version 1.0.0 - First Stable Release 🎉

Production-ready automation with Ansible-based tool installation, comprehensive error handling, and full idempotence.

---

## Overview

This directory contains scripts that automate the complete setup of a DevOps lab VM:

1. **labtomation.sh** - Main orchestration script
2. **setup_lab.sh** - Ansible and Python installation
3. **playbooks/** - Ansible playbooks for DevOps tools
4. **config/** - Configuration files for OS and hardware
5. **\*_lib.sh** - Reusable function libraries

---

## Quick Start

### Quick Installation (Recommended) ⭐

Use the auto-installer from the project root:

```bash
# From GitHub (one command)
curl -fsSL https://raw.githubusercontent.com/rollingafull/labtomation/main/install.sh | bash

# Or with options
./install.sh --os rocky10 --cores 4 --memory 16384
```

The installer automatically clones the repo, runs setup, and cleans up.

### Manual Usage

```bash
cd setup
./labtomation.sh
```

Interactive mode will prompt for:

- Operating System (**Rocky Linux 10** recommended, also Debian 13 or Ubuntu 24.04)
- VM configuration (cores, memory, disk)

### CLI Mode

```bash
# Recommended: Rocky Linux 10 (enterprise-grade, RHEL-based)
./labtomation.sh --os rocky10

# Alternative OS options
./labtomation.sh --os debian13    # Debian 13 (Trixie)
./labtomation.sh --os ubuntu2404  # Ubuntu 24.04 LTS

# Custom configuration with Rocky (recommended)
./labtomation.sh --name mylab --os rocky10 --cores 4 --memory 8192 --disk 50

# Specify VMID and storage
./labtomation.sh --vmid 200 --storage local-zfs --os rocky10
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--vmid <id>` | VM ID | Auto-generated |
| `--name <name>` | VM name | labtomation |
| `--os <os>` | OS: **rocky10** (recommended), debian13, ubuntu2404 | Interactive |
| `--cores <num>` | CPU cores | 2 |
| `--memory <mb>` | Memory in MB | 8192 |
| `--disk <gb>` | Disk size in GB | 32 |
| `--storage <name>` | Storage name | Auto-detected |
| `--force` | Force recreate if exists | No |

---

## What Gets Installed

### Base System (via Bash)

- Ansible (ansible-core for Rocky 9+, ansible for Debian/Ubuntu)
- Python 3 + pip
- Python packages: jmespath, netaddr

### DevOps Tools (via Ansible)

- **Terraform** - Infrastructure as Code
- **HashiCorp Vault** - Secrets management (listening on 0.0.0.0:8200)
- **Jenkins** - CI/CD server (with Java 21)
- **Common utilities**: git, vim, btop, curl, wget, jq, unzip

### Automatic Configuration

- VM tags: OS type + installed services
- SSH keys generated automatically
- Cloud-init configuration
- Service auto-start on boot

---

## Supported Operating Systems

### Rocky Linux 10 ⭐ **RECOMMENDED**

**Why Rocky Linux is recommended:**

- **Enterprise-grade stability**: RHEL-based, production-ready
- **Long-term support**: Aligned with RHEL lifecycle
- **Package maturity**: Well-tested repositories (AppStream, EPEL)
- **Corporate adoption**: Widely used in enterprise environments
- **Best compatibility**: Optimal support for HashiCorp tools via RHEL 9 repos

**Technical details:**

- Uses ansible-core from AppStream
- HashiCorp tools from RHEL 9 repository
- Java 21 from Rocky repos
- EPEL repository auto-configured

### Debian 13 (Trixie)

**Alternative for Debian users:**

- Modern GPG key handling (gpg --dearmor)
- HashiCorp tools from official Debian repo
- Java 21 from Debian repos
- Latest packages, bleeding-edge features

### Ubuntu 24.04 LTS (Noble)

**Alternative for Ubuntu users:**

- Same as Debian 13 (modern apt security)
- Full compatibility with HashiCorp tools
- Java 21 support
- LTS version with 5-year support

---

## Architecture

### Script Flow

```text
labtomation.sh
  ├─→ Download cloud-init OS image
  ├─→ Create VM (Q35 + EFI)
  ├─→ Import and resize disk
  ├─→ Configure cloud-init
  ├─→ Start VM and wait for network
  ├─→ Copy setup scripts to VM
  └─→ SSH into VM
       ├─→ Run setup_lab.sh
       │    └─→ Install Ansible + Python
       └─→ Run Ansible playbook
            └─→ Install DevOps tools
```

### File Structure

**On Proxmox host:**

```text
setup/
├── labtomation.sh              # Main script
├── setup_lab.sh                # Ansible installation
├── common_lib.sh               # Logging, colors, helpers
├── vm_lib.sh                   # VM operations (create, configure, tags)
├── config/
│   ├── labtomation.conf        # Main configuration
│   ├── os_configs.conf         # OS definitions & URLs
│   ├── hardware_configs.conf   # VM hardware defaults
│   └── network_configs.conf    # Network & SSH settings
├── playbooks/
│   ├── setup_devops_tools.yml  # Main playbook
│   ├── inventory/
│   │   └── localhost.yml       # Inventory file (auto-generated)
│   ├── group_vars/
│   │   └── all.yml             # Global variables
│   └── roles/
│       ├── common/             # System packages & EPEL
│       ├── terraform/          # Terraform installation
│       ├── vault/              # Vault installation & config
│       └── jenkins/            # Jenkins installation
├── logs/                       # Execution logs (auto-managed)
└── state/                      # Runtime state (auto-managed)
```

**On created VM (FHS-compliant installation):**

```text
/opt/labtomation/
├── setup_lab.sh                # Ansible installation script
├── common_lib.sh               # Library functions
├── config/
│   ├── os_configs.conf         # OS configurations
│   ├── hardware_configs.conf   # Hardware settings
│   └── network_configs.conf    # Network settings
└── playbooks/
    ├── setup_devops_tools.yml  # Main playbook
    ├── inventory/
    │   └── localhost.yml       # Localhost inventory
    ├── group_vars/
    │   └── all.yml             # Ansible variables
    └── roles/
        ├── common/
        ├── terraform/
        ├── vault/
        └── jenkins/
```

---

## Features

### Idempotence

Safe to run multiple times:

- Detects existing VMs and completes missing steps
- Skips already installed tools
- No errors on re-execution
- Use `--force` to recreate from scratch

See [IDEMPOTENCE.md](IDEMPOTENCE.md) for complete documentation.

### Automatic VM Tags

Each VM gets tagged with:

- **OS**: rocky10, debian13, or ubuntu2404
- **Services**: ansible, terraform, vault, jenkins

Example: `ubuntu2404;ansible;terraform;vault;jenkins`

### Error Handling

- Comprehensive error messages
- Failed tasks don't stop unrelated operations
- Logs saved to `logs/labtomation_YYYY-MM-DD_HH-MM-SS.log`
- State files for debugging in `state/`

### Security

- SSH keys with proper permissions (600)
- Vault listens on all interfaces for lab access
- Jenkins with latest security updates
- Cloud-init user with sudo access

---

## Requirements

### Proxmox Host

- Proxmox VE 7.0+ (for Q35+EFI support)
- Storage with 10GB+ free space
- Internet access for downloads

### Tools (usually pre-installed)

- qm, pvesh - Proxmox VM management
- jq - JSON processing
- wget - File downloads
- gpg - GPG key management

---

## Configuration Files

### config/os_configs.conf

Defines OS download URLs, default users, and display names.

### config/hardware_configs.conf

VM hardware defaults (CPU, machine type, BIOS, VGA, etc.).

### config/network_configs.conf

Network bridge, SSH settings, and key locations.

### config/labtomation.conf

Main configuration (currently unused, reserved for future features).

---

## Troubleshooting

### VM Doesn't Get IP

- Wait 2-3 minutes for cloud-init
- Check `qm agent <vmid> network-get-interfaces`
- Ensure bridge has network connectivity

### Ansible Installation Fails on Rocky 10

- Script auto-detects and uses ansible-core
- EPEL not required for Rocky 9+

### HashiCorp Tools Install Fails

- Script uses RHEL 9 repo for Rocky 10+
- Modern GPG key handling for Debian/Ubuntu
- Check internet connectivity

### Jenkins Won't Start

- Java 21 installed automatically
- Check `systemctl status jenkins`
- View logs: `journalctl -u jenkins -n 50`

### Vault Not Accessible Externally

- Configured to listen on 0.0.0.0:8200
- Check firewall rules on Proxmox/VM
- Access: `http://<vm-ip>:8200`

---

## Examples

### Create Lab with Specific VMID

```bash
./labtomation.sh --vmid 100 --os rocky10
```

### Large VM for Heavy Workloads

```bash
./labtomation.sh --cores 8 --memory 16384 --disk 100 --os ubuntu2404
```

### Multiple Labs

```bash
# Auto-generates different VMIDs
./labtomation.sh --name lab-dev --os debian13
./labtomation.sh --name lab-staging --os ubuntu2404
./labtomation.sh --name lab-prod --os rocky10
```

### Recreate Existing VM

```bash
./labtomation.sh --vmid 100 --os rocky10 --force
```

---

## Accessing Services

After successful setup:

### SSH Access

```bash
ssh -i ~/.ssh/id_rsa_labtomation <user>@<vm-ip>
```

Default user:

- All OS: `labtomation`

### HashiCorp Vault

1. Access UI: `http://<vm-ip>:8200`
2. Initialize Vault:

   ```bash
   export VAULT_ADDR='http://<vm-ip>:8200'
   vault operator init
   ```

3. Save unseal keys and root token!

### Jenkins

1. Access UI: `http://<vm-ip>:8080`
2. Get initial password:

   ```bash
   ssh <user>@<vm-ip> "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
   ```

3. Complete setup wizard

### Terraform

```bash
ssh <user>@<vm-ip>
terraform version
```

---

## Advanced Usage

### Using Ansible Playbooks Independently

You can run the playbooks on any existing system:

```bash
# Copy playbooks to target
scp -r playbooks/ user@target:/opt/labtomation/

# SSH to target
ssh user@target

# Run playbook
cd /opt/labtomation/playbooks
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml

# Install only specific tools
ansible-playbook setup_devops_tools.yml --tags terraform
ansible-playbook setup_devops_tools.yml --tags vault,jenkins
```

### Customizing Installations

Edit `playbooks/group_vars/all.yml`:

```yaml
# Disable Jenkins
install_jenkins: false

# Custom Vault configuration
vault_address: "127.0.0.1"  # Localhost only
vault_port: 8200

# Custom Jenkins configuration
jenkins_port: 9090
```

---

## Development

### Adding New OS Support

1. Add configuration to `config/os_configs.conf`:

   ```bash
   newos_vm_url="https://..."
   newos_vm_file="newos.qcow2"
   newos_default_user="admin"
   newos_display_name="New OS"
   ```

2. Update OS selection in `labtomation.sh` (select_os function)

3. Test Ansible playbook compatibility

### Adding New Tools

1. Create new role in `playbooks/roles/newtool/`
2. Add role to `playbooks/setup_devops_tools.yml`
3. Add configuration to `playbooks/group_vars/all.yml`
4. Test on all supported OS types

---

## Known Limitations

- Does not support LXC containers (VM only)
- Requires cloud-init images (traditional ISOs not supported)
- Vault starts unsealed (requires manual initialization)
- Jenkins requires manual setup wizard
- No automatic SSL/TLS configuration

---

## Version History

### 1.0.0 (2025-10-23) - First Stable Release 🎉

**Foundation Complete:**
- Automated management VM creation with Q35 + EFI
- DevOps toolchain pre-installed (Ansible, Terraform, Vault, Jenkins)
- Multi-OS support (Rocky 10, Debian 13, Ubuntu 24.04)
- One-command installer with auto-cleanup
- FHS-compliant installation paths (/opt/labtomation/)
- SSH key management and automatic generation
- Service-based tagging system
- Full idempotence across all operations
- Comprehensive documentation in English

**Key Features:**
- Fixed disk resize issue (qm disk resize implementation)
- Modern GPG key handling for Debian/Ubuntu
- Java 21 for Jenkins (official recommendation)
- Vault configured for external access (0.0.0.0:8200)
- EPEL auto-installation for Rocky Linux
- Modular Ansible roles architecture
- 8GB RAM default (optimal for DevOps tools)

### 2.1.0 (2025-10-20)

- Direct VM creation (no templates)
- Q35 + EFI support
- Removed LXC support
- Streamlined workflow

---

## Support

For issues, suggestions, or contributions:

- Check logs in `logs/` directory
- Review state files in `state/` directory
- Verify Proxmox version compatibility
- Ensure internet connectivity

---

## License

Internal use. All rights reserved.

## Author

rolling <rolling@a-full.com>
