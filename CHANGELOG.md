<div align="center">

![Labtomation Logo](assets/logo-horizontal.svg)

</div>

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
