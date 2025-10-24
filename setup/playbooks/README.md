<div align="center">

![Labtomation Logo](../../assets/logo-horizontal.svg)

</div>

# Ansible Playbooks for DevOps Tools

These playbooks install and configure DevOps tools on lab VMs created with Labtomation.

## 📋 Contents

### Main Playbook

- **`setup_devops_tools.yml`** - Complete DevOps tools installation

### Available Roles

1. **`common`** - Base system configuration and common packages
2. **`terraform`** - HashiCorp Terraform installation
3. **`vault`** - HashiCorp Vault installation and configuration
4. **`jenkins`** - Jenkins CI/CD installation (optional)

## 🚀 Usage

### Complete Installation

Installs all tools (Terraform + Vault):

```bash
cd /opt/labtomation/playbooks
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml
```

### Selective Installation with Tags

#### Terraform Only

```bash
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml --tags terraform
```

#### Vault Only

```bash
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml --tags vault
```

#### Terraform and Vault

```bash
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml --tags terraform,vault
```

#### Include Jenkins

```bash
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml -e "install_jenkins=true"
```

### Dry-Run Mode (Check)

Verify what changes would be made without applying them:

```bash
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml --check
```

### Verbose Mode

To see more details during execution:

```bash
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml -v   # Verbose
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml -vv  # More verbose
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml -vvv # Debug
```

## ⚙️ Configuration

### Global Variables

Edit `group_vars/all.yml` to customize:

```yaml
# Enable Jenkins
install_jenkins: true

# Specific versions
terraform_version: "1.6.0"
vault_version: "1.15.0"

# Ports
jenkins_port: 8080

# Vault directories
vault_config_dir: "/etc/vault.d"
vault_data_dir: "/opt/vault/data"
```

### Inventory

The `inventory/localhost.yml` file is automatically created by `labtomation.sh`:

```yaml
---
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
```

## 🔧 Roles in Detail

### Role: common

**Purpose:** Base system configuration

**Tasks:**

- Updates package cache
- Installs common packages (curl, wget, git, vim, btop, jq, unzip)
- Installs EPEL on Rocky Linux
- Verifies system directories

**Tags:** `common`, `always`

### Role: terraform

**Purpose:** Installs HashiCorp Terraform

**Tasks:**

- Adds HashiCorp repository (RHEL 9 for Rocky 10+)
- Installs Terraform via package manager
- Configures autocompletion
- Verifies installation

**Tags:** `terraform`, `devops`

**Verification:**

```bash
terraform version
```

### Role: vault

**Purpose:** Installs and configures HashiCorp Vault

**Tasks:**

- Adds HashiCorp repository
- Installs Vault via package manager
- Creates user and directories
- Configures configuration file (listens on 0.0.0.0:8200)
- Creates systemd service
- Starts Vault service

**Tags:** `vault`, `devops`

**Files created:**

- `/etc/vault.d/vault.hcl` - Configuration
- `/opt/vault/data` - Storage
- `/etc/systemd/system/vault.service` - Service

**Verification:**

```bash
vault version
systemctl status vault
export VAULT_ADDR='http://<vm-ip>:8200'
vault status
```

**Initialization:**

```bash
export VAULT_ADDR='http://<vm-ip>:8200'
vault operator init
# Save the unseal keys and root token!
```

### Role: jenkins

**Purpose:** Installs Jenkins CI/CD server

**Tasks:**

- Installs Java 21 (OpenJDK 21)
- Adds Jenkins repository (modern GPG keys)
- Installs Jenkins
- Starts Jenkins service
- Displays initial password

**Tags:** `jenkins`, `devops`, `optional`

**Requires:** Variable `install_jenkins=true` (now enabled by default)

**Verification:**

```bash
systemctl status jenkins
# Access http://<vm-ip>:8080
```

**Initial password:**

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

## 📦 File Structure

```text
playbooks/
├── setup_devops_tools.yml          # Main playbook
├── group_vars/
│   └── all.yml                     # Global variables
├── inventory/
│   └── localhost.yml               # Local inventory (auto-generated)
│
└── roles/
    ├── common/
    │   ├── tasks/main.yml
    │   └── defaults/main.yml
    ├── terraform/
    │   ├── tasks/main.yml
    │   └── defaults/main.yml
    ├── vault/
    │   ├── tasks/main.yml
    │   ├── defaults/main.yml
    │   ├── templates/
    │   │   ├── vault.hcl.j2
    │   │   └── vault.service.j2
    │   └── handlers/main.yml
    └── jenkins/
        ├── tasks/main.yml
        └── defaults/main.yml
```

## 🔍 Troubleshooting

### Ansible Can't Find Python

```bash
# Specify Python interpreter
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml \
  -e "ansible_python_interpreter=/usr/bin/python3"
```

### Vault Won't Start

```bash
# Check logs
sudo journalctl -u vault -f

# Verify configuration
sudo vault -config=/etc/vault.d/vault.hcl -verify-only

# Check permissions
sudo chown -R vault:vault /opt/vault/data
sudo chown -R vault:vault /etc/vault.d
```

### Jenkins Not Accessible

```bash
# Check service
sudo systemctl status jenkins

# Check port
sudo ss -tlnp | grep 8080

# Check firewall (if active)
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
```

### GPG Key Errors (Debian/Ubuntu)

The playbooks use modern GPG key handling with `gpg --dearmor` for Debian 13 and Ubuntu 24.04. If you encounter GPG errors:

```bash
# Verify GPG is installed
which gpg

# Check keyrings directory
ls -la /usr/share/keyrings/
```

## ✨ Features

✅ **Idempotent** - Can be run multiple times without issues

✅ **Modular** - Install only what you need with tags

✅ **Multi-OS** - Supports Rocky Linux 10, Debian 13, Ubuntu 24.04

✅ **Verifications** - Detects existing installations

✅ **Configurable** - Variables for customization

✅ **Documented** - Comments in each role

✅ **Modern** - Uses latest best practices (Java 21, GPG dearmor, etc.)

## 🎯 Practical Examples

### Update Terraform Only

```bash
# Re-run Terraform role (idempotent)
cd /opt/labtomation/playbooks
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml --tags terraform
```

### Install Everything Including Jenkins

```bash
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml -e "install_jenkins=true"
```

### Verify What Will Be Installed

```bash
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml --check --diff
```

### Reinstall Vault

```bash
# Stop service
sudo systemctl stop vault

# Clean data (WARNING: you'll lose data)
sudo rm -rf /opt/vault/data/*

# Re-run playbook
cd /opt/labtomation/playbooks
ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml --tags vault
```

## 🌐 OS-Specific Notes

### Rocky Linux 10

- Uses `ansible-core` from AppStream
- HashiCorp repos use RHEL 9 URLs
- EPEL auto-installed by common role
- Java 21 from Rocky repos

### Debian 13 (Trixie)

- Modern GPG key handling with `gpg --dearmor`
- GPG keys stored in `/usr/share/keyrings/`
- No `software-properties-common` needed
- Java 21 via `openjdk-21-jre`

### Ubuntu 24.04 LTS (Noble)

- Same modern GPG handling as Debian 13
- Fully compatible with all tools
- Java 21 support verified

## 📚 References

- [Ansible Documentation](https://docs.ansible.com/)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Vault Documentation](https://www.vaultproject.io/docs)
- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Labtomation Main README](../../README.md)

## 👤 Author

rolling <rolling@a-full.com>

## 📝 Version

**v1.0.0** - 2025-10-23 - First Stable Release 🎉

### What's New in 1.0.0

- Production-ready playbooks with full idempotence
- FHS-compliant installation paths (`/opt/labtomation/`)
- Default user `labtomation` across all OS
- Modern GPG key handling for Debian 13 & Ubuntu 24.04
- Java 21 for Jenkins (official recommendation)
- Vault configured for external access (0.0.0.0:8200)
- Service-based tagging system
- Comprehensive documentation in English
- Rocky Linux 10 fully supported and recommended
