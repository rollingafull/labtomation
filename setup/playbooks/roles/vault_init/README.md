# Vault Init Role

## Description

This role initializes and secures HashiCorp Vault after installation. It creates a secure directory structure, backs up SSH keys, initializes Vault, and stores credentials securely.

## Features

- ✅ Creates secure directory structure (`/home/labtomation/.security/`)
- ✅ Backs up SSH keys with immutable flags
- ✅ Initializes Vault automatically
- ✅ Stores Vault credentials securely
- ✅ Auto-unseals Vault using stored keys
- ✅ Creates environment file for easy CLI access
- ✅ Verifies security configuration
- ✅ Displays comprehensive summary

## Requirements

- HashiCorp Vault installed and running
- Vault service accessible at `http://127.0.0.1:8200`
- SSH keys generated (will be moved to secure directory during initialization):
  - `lab_id_ed25519` (for lab VMs/LXC)
  - `pve_id_ed25519` (for Proxmox nodes)

## Role Variables

See [defaults/main.yml](defaults/main.yml) for all available variables.

### Key Variables

```yaml
# Vault configuration
vault_addr: "http://127.0.0.1:8200"

# Security directory
security_dir: "/home/labtomation/.security"

# SSH key paths (stored in secure directory with 400 permissions + immutable)
lab_ssh_key_source: "/home/labtomation/.security/.lab_id_ed25519"
pve_ssh_key_source: "/home/labtomation/.security/.pve_id_ed25519"

# Credentials files (all stored securely with 400 permissions + immutable)
vault_creds_file: "/home/labtomation/.security/.vault"
vault_env_file: "/home/labtomation/.security/.vault_env.sh"

# Security settings
enable_immutable: true
```

## Usage

### In Playbook

This role is automatically included in `setup_devops_tools.yml` after the `vault` role:

```yaml
- role: vault
  tags: [vault, devops]

- role: vault_init
  tags: [vault, vault_init, devops]
```

### Standalone

```bash
cd /home/rolling/repos/labtomation/setup/playbooks
ansible-playbook -i localhost, -c local vault_init_standalone.yml
```

### Tags

- `security` - Security directory and SSH backup tasks
- `ssh_backup` - SSH key backup tasks only
- `vault_init` - Vault initialization tasks
- `unseal` - Vault unseal tasks

## Security Features

### Directory Structure

```
/home/labtomation/.security/
├── .lab_id_ed25519        # Backup of lab SSH private key (400, immutable)
├── .lab_id_ed25519.pub    # Backup of lab SSH public key (400, immutable)
├── .pve_id_ed25519        # Backup of PVE SSH private key (400, immutable)
├── .pve_id_ed25519.pub    # Backup of PVE SSH public key (400, immutable)
├── .vault                 # Vault credentials (400, immutable)
├── .vault_env.sh          # Vault environment file (400, hidden)
└── vault_init_summary.log # Initialization summary (600)
```

### Immutable Files

Critical files are protected with `chattr +i` to prevent accidental deletion:

- SSH key backups
- Vault credentials file

To modify these files:

```bash
# Remove immutable flag
sudo chattr -i /home/labtomation/.security/.vault

# Make changes
vim /home/labtomation/.security/.vault

# Restore immutable flag
sudo chattr +i /home/labtomation/.security/.vault
```

## Vault Credentials File Format

The `.vault` file contains:

```
token=<root_token>
unseal_key_1=<key1>
unseal_key_2=<key2>
unseal_key_3=<key3>
unseal_key_4=<key4>
unseal_key_5=<key5>
vault_addr=http://127.0.0.1:8200
initialized=<timestamp>
```

## Using Vault After Initialization

### Source Environment File

```bash
source /home/labtomation/.security/.vault_env.sh
```

This sets:
- `VAULT_ADDR` - Vault server address
- `VAULT_TOKEN` - Root token for authentication
- Helper functions: `vault_status`, `vault_unseal`

### Check Vault Status

```bash
vault status
# or
vault_status
```

### Unseal Vault (if sealed)

```bash
vault_unseal
```

## Tasks Overview

1. **create_security_dir.yml** - Creates secure directory structure
2. **backup_ssh_keys.yml** - Backs up SSH keys with immutable flags
3. **wait_for_vault.yml** - Waits for Vault service to be ready
4. **check_vault_status.yml** - Checks if Vault is initialized/sealed
5. **initialize_vault.yml** - Initializes Vault and saves credentials
6. **unseal_vault.yml** - Auto-unseals Vault using stored keys
7. **create_vault_env.yml** - Creates environment file for CLI access
8. **verify_security.yml** - Verifies security configuration
9. **display_summary.yml** - Displays initialization summary

## Error Handling

- Skips initialization if Vault is already initialized
- Handles sealed Vault state automatically
- Temporarily removes immutable flags when needed
- Verifies all security configurations
- Provides detailed error messages

## Author

**rolling** (rolling@a-full.com)

## Version

2.0.0 - Vault initialization and security automation

## License

MIT
