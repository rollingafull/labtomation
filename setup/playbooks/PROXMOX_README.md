# Proxmox Cluster Management with Labtomation

Automated discovery, bootstrap, and management of Proxmox VE clusters using Ansible and HashiCorp Vault.

<div align="center">

![Labtomation Logo](../../assets/logo-horizontal.svg)

**Version 2.0.0** - Proxmox Integration

</div>

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Playbooks](#playbooks)
- [Roles](#roles)
- [Vault Integration](#vault-integration)
- [Usage Examples](#usage-examples)
- [Troubleshooting](#troubleshooting)
- [Security](#security)

---

## 🎯 Overview

This suite of Ansible playbooks provides **complete automation** for Proxmox VE cluster management:

### Key Features

✅ **AppRole Authentication** - Production-ready Vault integration with AppRole
✅ **Automatic Discovery** - Network scanning to find all Proxmox nodes
✅ **Zero-Touch Bootstrap** - Fully automated setup from discovery to production
✅ **SSH Key Management** - Automated distribution of existing SSH keys
✅ **API Token Generation** - Automatic creation and Vault storage
✅ **Idempotent Operations** - Safe to run multiple times
✅ **Security Hardening** - Adds labtomation user, root SSH unchanged
✅ **Real Hostnames** - Uses actual node hostnames (not pve1, pve2...)
✅ **Granular Sudo** - Limited sudo permissions for specific commands only

### What Gets Automated

1. **Vault Setup**: AppRole configuration for secure secrets management
2. **Network Discovery**: Scans your network to find Proxmox nodes
3. **Node Validation**: Verifies each node is actually Proxmox VE
4. **User Creation**: Creates `labtomation` user on each node
5. **SSH Configuration**: Deploys SSH keys and disables password auth
6. **API Setup**: Creates Proxmox API users and generates tokens
7. **Vault Storage**: Saves all credentials securely in Vault
8. **Security Hardening**: Adds labtomation user with key-based auth

---

## 🏗️ Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│                        Labtomation VM                            │
│  ┌─────────────────┐  ┌──────────────┐  ┌───────────────────┐    │
│  │   Ansible       │  │    Vault     │  │   SSH Keys        │    │
│  │   Playbooks     │◄─┤   AppRole    │  │   id_ed25519      │    │
│  └────────┬────────┘  └──────────────┘  └───────────────────┘    │
└───────────┼──────────────────────────────────────────────────────┘
            │
            │ SSH (Key-based) + API (Token-based)
            ▼
┌──────────────────────────────────────────────────────────────────┐
│                        Proxmox Nodes                             │
│  ┌────────────────┐  ┌───────────────┐  ┌───────────────┐        │
│  │ homelab-node01 │  │ homelab-node02│  │ homelab-node03│        │
│  │                │  │               │  │               │        │
│  │ • labtomation  │  │ • labtomation │  │ • labtomation │        │
│  │   user + sudo  │  │   user + sudo │  │   user + sudo │        │
│  │ • SSH key      │  │ • SSH key     │  │ • SSH key     │        │
│  │ • API token    │  │ • API token   │  │ • API token   │        │
│  └────────────────┘  └───────────────┘  └───────────────┘        │
└──────────────────────────────────────────────────────────────────┘
            │
            │ Credentials stored in Vault
            ▼
    secret/proxmox/nodes/
    ├── homelab-node01/
    │   ├── api_token_id
    │   ├── api_token_secret
    │   ├── hostname
    │   ├── ip_address
    │   └── proxmox_version
    ├── homelab-node02/
    └── homelab-node03/
```

---

## ✅ Prerequisites

### On Labtomation VM

1. **Vault Initialized and Unsealed** (automatically done by vault_init role)

   ```bash
   # Check Vault status
   source /home/labtomation/.security/.vault_env.sh
   vault status
   ```

   The vault_init role automatically:
   - Initializes Vault on first boot
   - Saves root credentials to `/home/labtomation/.security/.vault`
   - Auto-unseals using stored keys
   - Creates environment file for easy access

2. **SSH Keys Exist**

   ```bash
   ls -la /home/labtomation/.security/.lab_id_ed25519*   # For lab VMs/LXC
   ls -la /home/labtomation/.security/.pve_id_ed25519*   # For Proxmox nodes
   ```

3. **Required Packages** (auto-installed if missing)
   - `python3-hvac` - Vault Python client
   - `python3-proxmoxer` - Proxmox API client
   - `python3-requests` - HTTP library
   - `nmap` - Network scanner
   - `sshpass` - SSH password authentication
   - `ansible-core` - Ansible engine

4. **Ansible Collections** (auto-installed)
   - `community.hashi_vault`
   - `community.general`

### On Proxmox Nodes

- ✅ **Root SSH enabled** (unchanged - password auth maintained)
- ✅ **Port 8006 accessible** (Proxmox web UI)
- ✅ **Network connectivity** to Labtomation VM
- ✅ **Same root password** on all nodes (for initial bootstrap)

---

## 🚀 Quick Start

### Complete Bootstrap (Recommended)

```bash
# Navigate to playbooks directory
cd /opt/labtomation/playbooks

# Install required Ansible collections (first time only)
ansible-galaxy collection install -r requirements.yml

# Run complete bootstrap
ansible-playbook bootstrap_proxmox_cluster.yml
```

**The playbook will prompt you for:**

1. Vault root token (if not already logged in)
2. Network range to scan (e.g., `192.168.1.0/24`)
3. Temporary root password for Proxmox nodes

**What happens:**

1. ✅ Configures Vault with AppRole
2. ✅ Scans network for Proxmox nodes (port 8006)
3. ✅ Validates each discovered node
4. ✅ Bootstraps each node:
   - Creates `labtomation` user
   - Copies SSH key
   - Configures sudo
   - Creates API user and token
   - Saves to Vault
   - Adds labtomation user
5. ✅ Updates inventory for future use
6. ✅ Verifies access with new user

**Duration**: 2-5 minutes per node

---

## 📖 Playbooks

### `bootstrap_proxmox_cluster.yml`

**Complete automated bootstrap of Proxmox infrastructure**

#### Phases

1. **Vault Integration** - Setup AppRole authentication
2. **Discovery** - Scan network for Proxmox nodes
3. **Refresh Inventory** - Load discovered nodes
4. **Bootstrap** - Configure each node
5. **Update Inventory** - Switch to labtomation user
6. **Verify** - Test access with new credentials

#### Usage

```bash
# Full bootstrap
ansible-playbook bootstrap_proxmox_cluster.yml

# Only Vault setup
ansible-playbook bootstrap_proxmox_cluster.yml --tags vault

# Only discovery
ansible-playbook bootstrap_proxmox_cluster.yml --tags discovery

# Only bootstrap (skip Vault/discovery)
ansible-playbook bootstrap_proxmox_cluster.yml --tags bootstrap

# Verify only
ansible-playbook bootstrap_proxmox_cluster.yml --tags verify
```

### `manage_proxmox_vms.yml`

**Manage VMs using Proxmox API**

#### Usage

```bash
# Source Vault credentials
source /opt/labtomation/.env

# Create a VM
ansible-playbook manage_proxmox_vms.yml \
  -e "target_node=homelab-node01" \
  -e "vm_name=web01" \
  -e "vm_cores=4" \
  -e "vm_memory=8192" \
  -e "vm_disk=50G"

# List all VMs
ansible-playbook manage_proxmox_vms.yml --tags list

# Delete a VM
ansible-playbook manage_proxmox_vms.yml \
  -e "target_node=homelab-node01" \
  -e "vm_name=web01" \
  -e "vm_state=absent"
```

---

## 🔧 Roles

### `vault_integration`

**Configure HashiCorp Vault with AppRole authentication**

#### What it does

- ✅ Checks Vault status (installed, unsealed, initialized)
- ✅ Installs Python `hvac` library
- ✅ Installs Ansible collections
- ✅ Enables AppRole auth method
- ✅ Creates policy for Ansible (`ansible-proxmox-policy`)
- ✅ Creates AppRole (`ansible-automation`)
- ✅ Generates Role ID and Secret ID
- ✅ Saves credentials to `/opt/labtomation/.env`
- ✅ Configures `ansible.cfg`
- ✅ Verifies integration with test write/read

#### Key Variables

```yaml
vault_addr: "http://127.0.0.1:8200"
vault_approle_name: "ansible-automation"
vault_approle_policy_name: "ansible-proxmox-policy"
vault_approle_token_ttl: "768h"  # 32 days
vault_approle_token_max_ttl: "8760h"  # 1 year
```

#### Files Created

- `/opt/labtomation/.vault-approle` - AppRole credentials
- `/opt/labtomation/.env` - Environment variables
- `/opt/labtomation/playbooks/ansible.cfg` - Ansible configuration
- `/opt/labtomation/playbooks/group_vars/all.yml` - Global variables

### `proxmox_discovery`

**Discover Proxmox VE nodes on the network**

#### What it does

- ✅ Installs `nmap` and `sshpass`
- ✅ Scans network range for port 8006
- ✅ Validates each discovered host via SSH
- ✅ Checks for `/etc/pve` directory
- ✅ Gets hostname, version, cluster info
- ✅ Generates inventory file

#### Key Variables

```yaml
proxmox_scan_port: 8006
discovery_ssh_timeout: 10
inventory_output_dir: /opt/labtomation/playbooks/inventory
inventory_file_name: proxmox_nodes.yml
```

#### Output

`/opt/labtomation/playbooks/inventory/proxmox_nodes.yml`

```yaml
proxmox_nodes:
  hosts:
    homelab-node01:
      ansible_host: 192.168.1.10
      proxmox_version: "8.2.4"
      proxmox_role: "standalone"
    homelab-node02:
      ansible_host: 192.168.1.11
      proxmox_version: "8.2.4"
      proxmox_role: "member"
      cluster_name: "homelab-cluster"
```

### `proxmox_bootstrap`

**Bootstrap Proxmox nodes for automation**

#### What it does

- ✅ Installs required packages (`python3-proxmoxer`, etc.)
- ✅ Creates `labtomation` OS user
- ✅ Copies SSH public key from Labtomation VM
- ✅ Configures sudo with granular permissions
- ✅ Creates Proxmox API user (`labtomation@pve`)
- ✅ Creates API role (`LabAutomation`) with permissions
- ✅ Generates API token
- ✅ Saves to Vault: `secret/proxmox/nodes/{hostname}`
- ✅ Adds labtomation user with key-based auth
- ✅ Disables password authentication

#### Key Variables

```yaml
labtomation_user: labtomation
pve_ssh_key_local: /home/labtomation/.security/.pve_id_ed25519
lab_ssh_key_local: /home/labtomation/.security/.lab_id_ed25519
proxmox_api_user: "labtomation@pve"
proxmox_api_token_name: labtomation-token
proxmox_api_role_name: LabAutomation
disable_root_ssh: false  # Keep root SSH enabled
```

#### Sudo Commands Allowed

```text
/usr/bin/apt
/usr/bin/apt-get
/usr/bin/systemctl
/usr/sbin/pveum
/usr/sbin/qm
/usr/sbin/pct
/usr/sbin/pvecm
/usr/sbin/pveversion
/usr/bin/cat /var/lib/jenkins/secrets/initialAdminPassword
```

#### API Role Permissions

**Compatible with Proxmox VE 8.x and 9.x**

```text
VM.Allocate, VM.Audit, VM.Config.*, VM.PowerMgmt, VM.Console
Datastore.Allocate, Datastore.AllocateSpace, Datastore.Audit
Pool.Allocate, Pool.Audit
SDN.Use
Sys.Audit, Sys.Modify
VM.Clone, VM.Migrate, VM.Snapshot, VM.Backup
```

**Note**: Proxmox VE 9.0 removed `VM.Monitor` privilege. Use `Sys.Audit` for monitor access.

### `proxmox_management`

**Ongoing management tasks**

#### What it does

- ✅ Update package cache
- ✅ Upgrade packages (optional)
- ✅ Monitor node status
- ✅ Backup `/etc/pve` (optional)

#### Key Variables

```yaml
update_cache: yes
upgrade_packages: no      # Set to yes to upgrade
enable_monitoring: yes
backup_etc_pve: no        # Set to yes to backup
backup_destination: /tmp/pve_backup
```

---

## 🔐 Vault Integration

### Credential Types

Labtomation uses **two separate sets** of Vault credentials:

#### 1. Root Credentials (Vault Administration)

**Location**: `/home/labtomation/.security/`

```bash
/home/labtomation/.security/.vault          # Root token + unseal keys
/home/labtomation/.security/.vault_env.sh   # Environment variables for root access (400)
```

**Purpose**:

- Vault initialization and unsealing
- Administrative operations
- Created automatically by vault_init role

**Usage**:

```bash
source /home/labtomation/.security/.vault_env.sh
vault status
```

#### 2. AppRole Credentials (Ansible Automation)

**Location**: `/opt/labtomation/`

```bash
/opt/labtomation/.vault-approle    # Role ID + Secret ID
/opt/labtomation/.env              # Exportable environment variables
```

**Purpose**:

- Ansible playbook authentication
- Proxmox integration automation
- Created automatically by vault_integration role

**Usage**:

```bash
source /opt/labtomation/.env
ansible-playbook bootstrap_proxmox_cluster.yml
```

### AppRole Authentication

Labtomation uses **AppRole** for production-ready Ansible automation:

```bash
# To use Vault with Ansible playbooks:
source /opt/labtomation/.env
vault status
```

### Vault Structure

```text
secret/data/proxmox/
├── bootstrap/
│   └── root_password         # Temporary (deleted after bootstrap)
└── nodes/
    ├── homelab-node01/
    │   ├── api_token_id      # labtomation@pve!labtomation-token
    │   ├── api_token_secret  # UUID
    │   ├── hostname          # homelab-node01
    │   ├── ip_address        # 192.168.1.10
    │   ├── proxmox_version   # 8.2.4
    │   ├── role              # standalone
    │   └── bootstrapped_at   # 2025-10-25T10:30:00Z
    └── homelab-node02/
        └── ...
```

### Manual Vault Operations

```bash
# List all Proxmox nodes
vault kv list secret/proxmox/nodes

# Get all credentials for a node
vault kv get secret/proxmox/nodes/homelab-node01

# Get only API token
vault kv get -field=api_token_secret secret/proxmox/nodes/homelab-node01

# Save a new secret
vault kv put secret/proxmox/nodes/new-node \
  api_token_id="labtomation@pve!token" \
  api_token_secret="uuid-here"
```

---

## 💡 Usage Examples

### Example 1: Fresh Setup

```bash
cd /opt/labtomation/playbooks

# Run complete bootstrap
ansible-playbook bootstrap_proxmox_cluster.yml

# When prompted:
# - Network range: 192.168.1.0/24
# - Root password: ********

# Wait for completion (~3 minutes per node)
```

### Example 2: Add New Node

```bash
# Re-run discovery to find new nodes
ansible-playbook bootstrap_proxmox_cluster.yml --tags discovery,bootstrap
```

### Example 3: Create VMs

```bash
# Source credentials
source /opt/labtomation/.env

# Create web server
ansible-playbook manage_proxmox_vms.yml \
  -e "target_node=homelab-node01" \
  -e "vm_name=web01" \
  -e "vm_cores=4" \
  -e "vm_memory=8192" \
  -e "vm_disk=100G"

# Create database server
ansible-playbook manage_proxmox_vms.yml \
  -e "target_node=homelab-node02" \
  -e "vm_name=db01" \
  -e "vm_cores=8" \
  -e "vm_memory=16384" \
  -e "vm_disk=200G"
```

### Example 4: Manage Nodes

```bash
# Source credentials
source /opt/labtomation/.env

# Update all nodes
ansible proxmox_nodes -m apt -a "update_cache=yes upgrade=dist" -b

# Check Proxmox version
ansible proxmox_nodes -m command -a "pveversion" -b

# Check cluster status
ansible proxmox_nodes -m command -a "pvecm status" -b

# List VMs on all nodes
ansible proxmox_nodes -m command -a "qm list" -b

# Reboot all nodes (careful!)
ansible proxmox_nodes -m reboot -b
```

### Example 5: Rotate API Tokens

```bash
# Re-bootstrap specific node to rotate token
ansible-playbook bootstrap_proxmox_cluster.yml \
  --tags bootstrap \
  --limit homelab-node01
```

---

## 🐛 Troubleshooting

### Vault Issues

**Problem**: `Vault is sealed`

```bash
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>
vault status
```

**Problem**: `Permission denied` accessing secrets

```bash
# Check AppRole token
source /opt/labtomation/.env
vault token lookup

# Regenerate if expired
ansible-playbook bootstrap_proxmox_cluster.yml --tags vault
```

### Discovery Issues

**Problem**: No nodes found

```bash
# Manual nmap scan
nmap -p 8006 --open 192.168.1.0/24

# Check Proxmox web UI
curl -k https://192.168.1.10:8006

# Verify network range is correct
ip addr show
```

**Problem**: Nodes found but validation fails

```bash
# Test SSH manually
sshpass -p 'your-password' ssh root@192.168.1.10 'hostname'

# Check /etc/pve exists
sshpass -p 'your-password' ssh root@192.168.1.10 '[ -d /etc/pve ] && echo OK'
```

### Bootstrap Issues

**Problem**: SSH key authentication fails

```bash
# Check key exists
ls -la /home/labtomation/.security/.pve_id_ed25519*

# Keys should be protected (400 permissions + immutable)
# To check immutable flag: lsattr /home/labtomation/.security/.pve_id_ed25519

# Test manually
ssh -i /home/labtomation/.security/.pve_id_ed25519 labtomation@192.168.1.10
```

**Problem**: Sudo doesn't work

```bash
# Check sudoers file on Proxmox node
ssh labtomation@node 'sudo cat /etc/sudoers.d/labtomation'

# Test specific command
ssh labtomation@node 'sudo pvecm status'
```

### API Issues

**Problem**: API token doesn't work

```bash
# Get token from Vault
vault kv get secret/proxmox/nodes/homelab-node01

# Test API manually
curl -k -H "Authorization: PVEAPIToken=labtomation@pve!labtomation-token=<secret>" \
  https://192.168.1.10:8006/api2/json/nodes/homelab-node01/status
```

---

## 🔒 Security

### Authentication Methods

| Method | Use Case | Security Level |
|--------|----------|----------------|
| **SSH Keys** | OS access, maintenance | ⭐⭐⭐⭐⭐ High |
| **API Tokens** | VM management, automation | ⭐⭐⭐⭐⭐ High |
| **Vault AppRole** | Secrets management | ⭐⭐⭐⭐⭐ High |
| **Root Password** | Bootstrap only (temporary) | ⚠️ Avoid after setup |

### Security Hardening

✅ **Root SSH remains enabled** (key-based auth required)
✅ **Labtomation user added (key-based)**
✅ **Root: password, Labtomation: key-based**
✅ **Granular sudo permissions**
✅ **API tokens with limited scope**
✅ **All credentials in Vault**
✅ **No hardcoded secrets**

### Best Practices

1. **Rotate tokens regularly**

   ```bash
   ansible-playbook bootstrap_proxmox_cluster.yml --tags bootstrap --limit node
   ```

2. **Backup Vault**

   ```bash
   vault operator raft snapshot save backup-$(date +%Y%m%d).snap
   ```

3. **Monitor access**

   ```bash
   # On Proxmox nodes
   tail -f /var/log/auth.log
   ```

4. **Use separate AppRoles** for different teams/environments

---

## 🔗 Integration with Terraform

```hcl
# terraform/main.tf

# Read credentials from Vault
data "vault_generic_secret" "proxmox" {
  path = "secret/proxmox/nodes/homelab-node01"
}

provider "proxmox" {
  pm_api_url          = "https://${data.vault_generic_secret.proxmox.data["ip_address"]}:8006/api2/json"
  pm_api_token_id     = data.vault_generic_secret.proxmox.data["api_token_id"]
  pm_api_token_secret = data.vault_generic_secret.proxmox.data["api_token_secret"]
  pm_tls_insecure     = true
}

resource "proxmox_vm_qemu" "web" {
  name        = "web01"
  target_node = data.vault_generic_secret.proxmox.data["hostname"]
  cores       = 4
  memory      = 8192

  disk {
    size    = "50G"
    storage = "local-lvm"
  }
}
```

---

## 📚 References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Labtomation Main README](../../README.md)

---

## 👤 Author

**rolling** <rolling@a-full.com>

---

## 📝 License

Apache License 2.0 - See [LICENSE](../../LICENSE)

---

**Copyright © 2025 rolling**
