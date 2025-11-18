<div align="center">

![Labtomation Logo](assets/logo-horizontal.svg)

</div>

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0] - 2025-10-27 🎉

### Major Release - Proxmox Integration & Vault Automation

This is a major release that adds complete Proxmox cluster management capabilities and automated Vault initialization.

### Added

#### Proxmox Integration

- **Automated Proxmox Cluster Management**: Complete suite of Ansible playbooks for Proxmox VE cluster automation
  - `bootstrap_proxmox_cluster.yml` - Full cluster bootstrap automation
  - `manage_proxmox_vms.yml` - VM management via API
  - Network scanning and discovery of Proxmox nodes
  - Automatic API token generation and Vault storage

- **New Ansible Roles for Proxmox**:
  - `vault_integration` - AppRole authentication setup for Vault
  - `proxmox_discovery` - Network scanning to find Proxmox nodes
  - `proxmox_bootstrap` - Node configuration and user setup
  - `proxmox_management` - Ongoing VM/LXC management

- **SSH Key Management**:
  - Separated SSH keys for different purposes:
    - `lab_id_ed25519` - For lab VMs/LXC created with Terraform
    - `pve_id_ed25519` - For Proxmox node access
  - Automatic key generation and distribution
  - Secure backup with immutable flags

#### Vault Automation

- **vault_init Role**: Complete Vault initialization and security automation
  - Automatic Vault initialization on first boot
  - Secure credential storage in `/home/labtomation/.security/.vault`
  - Auto-unseal using stored keys (3 of 5)
  - SSH key backup with immutable flags (`chattr +i`)
  - Environment file creation for easy CLI access
  - Comprehensive security verification

- **Security Directory Structure**:
  - Created `/home/labtomation/.security/`
  - Hidden files for SSH keys and credentials
  - Immutable flags on critical files

- **Vault Integration**:
  - AppRole authentication for production security
  - Automatic token management
  - Playbooks can read Vault credentials automatically
  - Environment file for manual access: `.vault_env.sh` (hidden, 400 permissions)

#### Documentation

- **PROXMOX_README.md**: Comprehensive guide for Proxmox integration
  - Architecture diagrams
  - Quick start guide
  - Security features documentation
  - Troubleshooting section

- **vault_init Role Documentation**:
  - README.md - Complete role documentation
  - TESTING.md - Testing guide and validation results

- **Test Playbooks**:
  - `test_vault_init.yml` - Standalone testing for vault_init role

### Changed

- **labtomation.sh v2.0.0**:
  - Removed inline bash security script
  - Now uses vault_init Ansible role for security setup
  - Updated to copy SSH keys to VM for role consumption
  - Enhanced final summary with new security features

- **setup_devops_tools.yml**:
  - Added vault_init role execution after vault installation
  - Updated post-installation summary
  - Added vault_init tag support

- **Vault Configuration**:
  - Credentials file format updated for easier parsing
  - Environment file includes helper functions
  - Auto-unseal on system startup

### Security Enhancements

- **Immutable File Protection**: Critical files protected with `chattr +i`
  - Vault credentials
  - SSH key backups
  - Prevents accidental deletion or modification

- **Granular Sudo Permissions**: Labtomation user on Proxmox nodes
  - Limited to specific commands only
  - No full root access
  - Auditable command execution

- **AppRole Authentication**: Production-ready Vault authentication
  - Service-to-service authentication
  - Limited scope and permissions
  - Automatic token renewal

- **Credential Segregation**: Separate credentials for different purposes
  - SSH keys for different access levels
  - API tokens for automation
  - All stored securely in Vault

### Infrastructure

- **Modular Architecture**: Clean separation of concerns
  - VM creation (labtomation.sh)
  - Tool installation (setup_devops_tools.yml)
  - Security setup (vault_init role)
  - Proxmox management (dedicated playbooks)

- **Idempotent Operations**: All new playbooks are idempotent
  - Safe to run multiple times
  - Proper state detection
  - No duplicate resources

### Testing

- **Comprehensive Testing**:
  - Syntax validation for all new playbooks
  - YAML structure validation
  - Test playbooks for independent role testing
  - Documented testing procedures

### Breaking Changes

- **SSH Key Names Changed**:
  - `id_ed25519` → `lab_id_ed25519` (for lab VMs/LXC)
  - New `pve_id_ed25519` (for Proxmox nodes)
  - Automatic migration in new installations

- **Vault Credentials Location Changed**:
  - Old: `/home/labtomation/.vault_env`
  - New: `/home/labtomation/.security/.vault` (credentials)
  - New: `/home/labtomation/.security/.vault_env.sh` (environment, 400)

### Migration Guide

For existing v1.x installations:

1. **SSH Keys**: Rename existing keys or regenerate

   ```bash
   mv /opt/labtomation/setup/id_ed25519 /opt/labtomation/setup/lab_id_ed25519
   mv /opt/labtomation/setup/id_ed25519.pub /opt/labtomation/setup/lab_id_ed25519.pub
   ```

2. **Vault Initialization**: Run vault_init role manually

   ```bash
   cd /opt/labtomation/playbooks
   ansible-playbook test_vault_init.yml
   ```

3. **Update Scripts**: Pull latest version and re-run setup if needed

### Known Issues

- None reported

### Upgrade Path

**From v1.0.x to v2.0.0**:

- Recommended: Fresh installation for best experience
- Manual migration possible for existing VMs
- Vault data preserved if using same initialization keys

---

## [1.0.2] - 2025-10-24

### Removed

- **README.md**: Removed `curl | bash` installation method
  - Direct pipe method had buffering issues preventing final summary from displaying
  - Download method is more reliable and provides better user experience
  - Manual installation via git clone remains available as Option 2

### Changed

- **README.md**: Simplified installation instructions
  - Single recommended method: download and execute install.sh
  - Clearer instructions for both interactive and non-interactive modes

---

## [1.0.1] - 2025-10-24

### Fixed

- **SSH Key Generation**: Fixed critical bug where ssh-keygen output was captured in variables
  - Redirected ssh-keygen output to stderr (`>&2`) to prevent stdout pollution
  - SSH key path now correctly captured without mixed output
  - Cloud-init configuration no longer fails due to malformed key paths

- **Interactive Prompts in Pipe Mode**: Fixed all interactive prompts when using `curl | bash`
  - **install.sh**: Git installation prompt now uses `/dev/tty`
  - **labtomation.sh**: OS selection menu now uses `/dev/tty`
  - **labtomation.sh**: VM creation confirmation now uses `/dev/tty`
  - All user inputs work correctly even when stdin is piped
  - Maintains full interactive experience with one-command installation

### Changed

- **install.sh**: Improved user experience for one-command installation
  - Interactive prompts work reliably in both local and piped execution
  - Clear error messages when terminal is not available
  - Added comprehensive Vault initialization guide to final summary
    - Step-by-step unsealing process (3 of 5 keys)
    - Root token login instructions
    - Vault UI access information
- **labtomation.sh**: Enhanced interactive mode compatibility
  - OS selection and VM confirmation work with piped input
  - Consistent behavior across all execution methods

### Documentation

- **install.sh**: Enhanced post-installation guidance
  - Added detailed Vault initialization steps to final summary
  - Included Jenkins initial password retrieval instructions
  - Clearer SSH connection examples

---

## [1.0.0] - 2025-10-23 🎉

### First Stable Release

This is the first production-ready release of Labtomation, providing a complete foundation for homelab and small business infrastructure management.

### Added

#### Core Features

- **Automated VM Creation**: One-command deployment of management VM on Proxmox VE
- **Multi-OS Support**: Rocky Linux 10 (recommended), Debian 13 (Trixie), and Ubuntu 24.04 LTS
- **DevOps Toolchain**: Pre-installed and pre-configured tools
  - Ansible (ansible-core for Rocky, ansible for Debian/Ubuntu)
  - Terraform (latest from HashiCorp repositories)
  - HashiCorp Vault (configured for external access on 0.0.0.0:8200)
  - Jenkins (with Java 21 support)
  - Common utilities (git, vim, btop, curl, wget, jq, unzip)

#### Installation & Deployment

- **One-Command Installer**: `install.sh` script for automated setup from GitHub
- **Cloud-init Integration**: Fast, reproducible VM provisioning
- **Modern VM Configuration**: Q35 machine type with UEFI/OVMF BIOS
- **Automatic SSH Key Generation**: Ed25519 keys created and configured automatically
- **FHS-Compliant Paths**: Installation in `/opt/labtomation/` following Linux standards

#### Idempotence & Safety

- **Full Idempotence**: Safe to run scripts multiple times without side effects
- **State Management**: Intelligent detection of existing resources
- **Force Recreate Option**: `--force` flag for intentional VM replacement
- **Disk Resize Fix**: Proper implementation using `qm disk resize`
- **Boot Configuration**: Automatic and idempotent boot order setup
- **Cloud-init Handling**: Proper detection and configuration

#### Organization & Tagging

- **Service Tags**: VMs automatically tagged with OS type and installed services
  - OS tags: `rocky10`, `debian13`, `ubuntu2404`
  - Service tags: `ansible`, `terraform`, `vault`, `jenkins`
- **VMID Management**: Automatic cluster-aware VMID generation
- **Storage Detection**: Auto-detection of best available Proxmox storage

#### Configuration & Customization

- **Flexible Options**: Customize CPU, RAM, disk, storage, and VMID
- **Default User**: `labtomation` user across all operating systems
- **Default Resources**: 2 cores, 8GB RAM, 32GB disk (production-ready defaults)
- **Configuration Files**: Centralized in `setup/config/`
  - `os_configs.conf` - OS definitions and download URLs
  - `hardware_configs.conf` - VM hardware defaults
  - `network_configs.conf` - Network and SSH settings
  - `labtomation.conf` - Main configuration (reserved for future use)

#### Ansible Integration

- **Modular Roles**: Clean separation of concerns
  - `common` - Base system packages and EPEL (for Rocky Linux)
  - `terraform` - HashiCorp Terraform installation and autocomplete
  - `vault` - HashiCorp Vault installation and service configuration
  - `jenkins` - Jenkins with Java 21 installation
- **Idempotent Playbooks**: Safe to re-run without side effects
- **Tag Support**: Install specific tools using `--tags`
- **Modern Package Management**:
  - GPG key handling with `gpg --dearmor` for Debian/Ubuntu
  - RHEL 9 repositories for Rocky Linux 10+
  - Official HashiCorp repositories

#### Documentation

- **Comprehensive README**: Professional project documentation
- **Installation Guide**: Detailed setup instructions in `setup/README.md`
- **Idempotence Guide**: Complete documentation in `setup/IDEMPOTENCE.md`
- **Playbooks Guide**: Ansible documentation in `setup/playbooks/README.md`
- **Quick Reference Tables**: Common commands and options
- **Troubleshooting Sections**: OS-specific guidance

### Security

- **SSH Key Type**: Ed25519 keys (modern, secure)
- **Key Permissions**: Automatic setting of correct permissions (600 for private, 644 for public)
- **HashiCorp GPG Keys**: Verified signatures for package installation
- **Cloud-init Security**: Proper SSH key injection and user creation

### Documentation

- **Apache License 2.0**: Clearly documented in README with usage terms
- **Contributing Guidelines**: How to contribute to the project
- **Support Information**: Community and commercial support options
- **Roadmap**: Clear development path for future versions
- **Badges**: Visual indicators for license, OS support, and tools
- **Version History**: Consolidated changelog in all documentation files

### Infrastructure

- **GitHub Repository**: https://github.com/rollingafull/labtomation
- **Quick Installer**: Download and execute install.sh from GitHub
- **Automatic Cleanup**: Temporary files removed after installation (SSH keys preserved)

## [Unreleased]

### Infrastructure Templates

- Proxmox clusters integration management with API access and keys stored in Vault
- Creation of multiple Proxmox cloud-init templates (VM/LXC) for various OSes and configurations
- Kubernetes clusters
- Development/staging/production environments

### Configuration Management

- Application deployment
- Security hardening
- Monitoring stack (Prometheus, Grafana)
- Logging stack (ELK, Loki)
- Backup automation

### Vault integration

- Dynamic credentials for databases
- SSH certificate authority
- PKI infrastructure
- Encryption as a service

### CI/CD Pipelines

- Infrastructure validation
- Automated testing
- Deployment workflows
- Rollback procedures

## Release Notes

### Version 1.0.0 - Production Ready

Labtomation v1.0.0 represents a complete, production-ready solution for bootstrapping homelab and small business infrastructure. The focus has been on:

1. **Reliability**: Full idempotence ensures safe re-runs
2. **Compatibility**: Tested on Rocky 10, Debian 13, and Ubuntu 24.04
3. **Ease of Use**: One-command installation from GitHub
4. **Professional Standards**: FHS-compliant paths, proper permissions, modern tools
5. **Documentation**: Comprehensive guides in English

This release provides a solid foundation for:

- Homelab environments
- Small business infrastructure
- DevOps learning and testing
- Infrastructure as Code development
- CI/CD pipeline experimentation

### Upgrade Path

This is the first public release, so there is no upgrade path from previous versions.

Future versions will include:

- Migration scripts for major version changes
- Backward compatibility when possible
- Detailed upgrade documentation

## Links

- [GitHub Repository](https://github.com/rollingafull/labtomation)
- [Installation Guide](setup/README.md)
- [Idempotence Documentation](setup/IDEMPOTENCE.md)
- [Ansible Playbooks](setup/playbooks/README.md)
- [Issue Tracker](https://github.com/rollingafull/labtomation/issues)
- [License](LICENSE) - Apache 2.0

**Copyright © 2025 rolling**

Licensed under the Apache License, Version 2.0
