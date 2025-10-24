<div align="center">

![Labtomation Logo](assets/logo-horizontal.svg)

---

**Infrastructure as Code for Home Labs and Small Businesses**

Labtomation is an automation framework designed to simplify the deployment and management of homelab and small business infrastructure using modern DevOps practices. Built on Proxmox VE, it provides a streamlined path from bare metal to a fully functional infrastructure management platform.

</div>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE%208.0%2B-orange)](https://www.proxmox.com/)

**Supported Operating Systems:**

[![Rocky Linux](https://img.shields.io/badge/Rocky%20Linux-10-10B981?logo=rockylinux&logoColor=white)](https://rockylinux.org/)
[![Debian](https://img.shields.io/badge/Debian-13%20Trixie-A81D33?logo=debian&logoColor=white)](https://www.debian.org/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)

**Pre-installed DevOps Tools:**

[![Ansible](https://img.shields.io/badge/Ansible-Latest-EE0000?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Terraform](https://img.shields.io/badge/Terraform-Latest-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Vault](https://img.shields.io/badge/Vault-Latest-000000?logo=vault&logoColor=white)](https://www.vaultproject.io/)
[![Jenkins](https://img.shields.io/badge/Jenkins-Latest-D24939?logo=jenkins&logoColor=white)](https://www.jenkins.io/)

## 📖 Table of Contents

- [Overview](#overview)
- [Current Status](#current-status)
- [Features](#features)
- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)

## 🎯 Overview

Labtomation automates the creation of a **management VM** that serves as the foundation for your homelab or small business infrastructure. This management VM comes pre-configured with essential DevOps tools (Ansible, Terraform, Vault, Jenkins) and acts as your central control plane for infrastructure orchestration.

### What is Labtomation?

Think of Labtomation as your infrastructure bootstrap. Instead of manually installing and configuring multiple tools across different systems, Labtomation:

1. **Creates** a management VM on Proxmox with modern Q35 + EFI configuration
2. **Installs** industry-standard DevOps tools automatically
3. **Configures** everything to work together seamlessly
4. **Prepares** your environment for infrastructure automation

From this management VM, you'll be able to:

- Define infrastructure as code using **Terraform**
- Automate configuration management with **Ansible**
- Store secrets securely in **HashiCorp Vault**
- Implement CI/CD pipelines with **Jenkins**

## 🚀 Current Status

**Version:** 1.0.0 🎉

Labtomation has reached its **first stable release**, providing a solid foundation for homelab infrastructure management:

### ✅ What's Available Now (v1.0.0)

- **Automated VM Creation**: One-command deployment of management VM
- **DevOps Tooling**: Pre-installed Ansible, Terraform, Vault, and Jenkins
- **Multi-OS Support**: Rocky Linux 10 (recommended), Debian 13, Ubuntu 24.04
- **Cloud-init Integration**: Fast, reproducible VM provisioning
- **Idempotent Operations**: Safe to run multiple times
- **Automatic Tagging**: VMs tagged with OS and installed services

### 🔜 Coming Soon

Future versions will expand Labtomation into a complete infrastructure management solution:

- **Infrastructure Templates**: Pre-built Terraform modules for common scenarios

  - Proxmox clusters integration management with API access and keys stored in Vault
  - Creation of multiple Proxmox cloud-init templates (VM/LXC) for various OSes and configurations
  - Kubernetes clusters
  - Development/staging/production environments

- **Configuration Library**: Ready-to-use Ansible playbooks

  - Application deployment
  - Security hardening
  - Monitoring stack (Prometheus, Grafana)
  - Logging stack (ELK, Loki)
  - Backup automation

- **Vault Integration**: Secret management workflows

  - Dynamic credentials for databases
  - SSH certificate authority
  - PKI infrastructure
  - Encryption as a service

- **CI/CD Pipelines**: Jenkins pipeline templates

  - Infrastructure validation
  - Automated testing
  - Deployment workflows
  - Rollback procedures

## ✨ Features

### Current Features

- **🚀 One-Command Installation**: Deploy via curl or manual clone
- **🔧 Modern VM Configuration**: Q35 machine type with UEFI/OVMF BIOS
- **📦 Complete Toolchain**: Ansible, Terraform, Vault, Jenkins pre-configured
- **🔄 Idempotent Design**: Re-run safely without side effects
- **🏷️ Smart Tagging**: Automatic OS and service tags for organization
- **🔐 SSH Key Management**: Automatic generation and configuration
- **📊 Multi-OS Support**: Choose from Rocky Linux, Debian, or Ubuntu
- **⚙️ Customizable**: Configure CPU, RAM, disk, and storage options

### Technical Highlights

- **FHS-Compliant**: Follows Linux Filesystem Hierarchy Standard (`/opt/labtomation/`)
- **Ansible-Based**: Modular roles for maintainability and extensibility
- **Cloud-init**: Modern VM initialization for reproducibility
- **Well-Documented**: Comprehensive guides and inline documentation
- **Enterprise-Grade**: Production-ready default configurations

## 🚀 Quick Start

### Prerequisites

- **Proxmox VE** 8.0 or higher
- **Internet access** for downloading OS images
- **Storage**: At least 10GB free space
- **Network**: DHCP-enabled bridge (e.g., vmbr0)

### Option 1: Quick Installation (Recommended)

```bash
# Download installer
wget https://raw.githubusercontent.com/rollingafull/labtomation/main/install.sh
chmod +x install.sh

# Interactive mode (recommended for first-time users)
./install.sh

# Or with specific options (Rocky Linux recommended)
./install.sh --os rocky10 --cores 4 --memory 16384 --disk 50
```

### Option 2: Manual Installation

```bash
# Clone repository
git clone https://github.com/rollingafull/labtomation.git
cd labtomation/setup

# Run installer (interactive mode)
./labtomation.sh

# Or with options
./labtomation.sh --os rocky10 --cores 4 --memory 16384
```

### What Gets Installed

After installation, you'll have a fully functional management VM with:

| Tool | Purpose | Access |
|------|---------|--------|
| **Ansible** | Configuration management | SSH (ansible-core or ansible) |
| **Terraform** | Infrastructure as code | SSH (`terraform version`) |
| **Vault** | Secrets management | `http://<vm-ip>:8200` |
| **Jenkins** | CI/CD automation | `http://<vm-ip>:8080` |
| **Common Tools** | git, vim, curl, wget, jq, btop | SSH |

### Connecting to Your VM

```bash
# SSH into management VM (keys are in current directory)
ssh -i ./id_ed25519 labtomation@<vm-ip>

# Access Vault UI
http://<vm-ip>:8200

# Access Jenkins UI
http://<vm-ip>:8080
```

## 📋 Requirements

### Proxmox Host

- Proxmox VE 8.0+ (for Q35 + EFI support)
- Required commands: `qm`, `pvesh`, `wget`, `git`, `jq`
- Network bridge with DHCP (typically `vmbr0`)
- Sufficient resources for VM (minimum 2 cores, 8GB RAM, 32GB disk)

### Supported Operating Systems

| OS | Version | Status | Notes |
|----|---------|--------|-------|
| **Rocky Linux** | 10 | ⭐ **Recommended** | Enterprise-grade, RHEL-based stability |
| **Debian** | 13 (Trixie) | ✅ Supported | Latest packages, modern features |
| **Ubuntu** | 24.04 LTS | ✅ Supported | Long-term support, wide adoption |

**Why Rocky Linux is recommended:**

- Enterprise-grade stability (RHEL-based)
- Long-term support aligned with RHEL lifecycle
- Mature package repositories (AppStream + EPEL)
- Optimal compatibility with HashiCorp tools
- Widely adopted in corporate environments

## 🗺️ Roadmap

### Version 1.0.0 (Foundation) - ✅ Completed

- [x] Automated management VM creation
- [x] DevOps toolchain installation
- [x] Multi-OS support (Rocky 10, Debian 13, Ubuntu 24.04)
- [x] One-command installer
- [x] Comprehensive documentation
- [x] Idempotent operations
- [x] SSH key management
- [x] FHS-compliant installation paths

### Infrastructure Templates

- [ ] Terraform module library
  - [ ] Proxmox cluster integration
  - [ ] VM/LXC cloud-init templates
  - [ ] Kubernetes cluster deployment
- [ ] Pre-configured network topologies
- [ ] Storage management templates

### Configuration Management

- [ ] Ansible playbook collection
  - [ ] Application deployment playbooks
  - [ ] Application upgrade playbooks
  - [ ] Security hardening playbooks
  - [ ] Monitoring stack (Prometheus + Grafana)
  - [ ] Logging stack (ELK/Loki)
- [ ] Role-based access control
- [ ] Backup and disaster recovery automation

### Advanced Features

- [ ] Vault integration workflows
  - [ ] Dynamic database credentials
  - [ ] SSH CA implementation
  - [ ] PKI infrastructure
- [ ] Jenkins pipeline templates
  - [ ] Infrastructure testing
  - [ ] Automated deployments
  - [ ] Compliance validation
- [ ] Web-based management interface
- [ ] Multi-site support

## 📚 Documentation

### Core Documentation

- **[Installation Guide](setup/README.md)** - Detailed installation instructions and troubleshooting
- **[Idempotence Guide](setup/IDEMPOTENCE.md)** - Understanding idempotent operations and re-runs
- **[Ansible Playbooks](setup/playbooks/README.md)** - Playbook documentation and customization
- **[CHANGELOG](CHANGELOG.md)** - Version history and release notes

### Configuration Files

All configuration is centralized in `setup/config/`:

- `os_configs.conf` - Operating system definitions and URLs
- `hardware_configs.conf` - VM hardware defaults
- `network_configs.conf` - Network and SSH settings
- `labtomation.conf` - Main configuration (reserved for future use)

### Quick Reference

| Topic | Command/Location |
|-------|------------------|
| Create VM (interactive) | `./install.sh` |
| Create VM (Rocky Linux) | `./install.sh --os rocky10` |
| Custom resources | `./install.sh --cores 4 --memory 16384 --disk 50` |
| SSH to VM | `ssh -i ./id_ed25519 labtomation@<vm-ip>` |
| Vault UI | `http://<vm-ip>:8200` |
| Jenkins UI | `http://<vm-ip>:8080` |
| Re-run safely | `./labtomation.sh --vmid <id> --os rocky10` |
| Force recreate | `./labtomation.sh --vmid <id> --os rocky10 --force` |

## 🤝 Contributing

Contributions are welcome! Whether you're fixing bugs, improving documentation, or proposing new features, your help is appreciated.

### How to Contribute

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines

- Follow existing code style and conventions
- Update documentation for any new features
- Test changes on all supported OS platforms when possible
- Keep commits atomic and well-described
- Add comments for complex logic

### Reporting Issues

Found a bug or have a feature request? Please [open an issue](https://github.com/rollingafull/labtomation/issues) with:

- Clear description of the problem or suggestion
- Steps to reproduce (for bugs)
- Expected vs actual behavior
- Your environment (Proxmox version, OS, etc.)

## 📄 License

Labtomation is released under the **Apache License 2.0**.

This means you are free to:

- ✅ Use the software for any purpose (commercial or non-commercial)
- ✅ Modify the source code
- ✅ Distribute original or modified versions
- ✅ Include in proprietary software

Under the conditions:

- 📝 Include the license and copyright notice
- 📝 State significant changes made to the code
- 📝 Include a NOTICE file if one exists
- 📝 Provide attribution to the original authors

See the [LICENSE](LICENSE) file for the full license text.

**Copyright © 2025 rolling**

## 💬 Support

### Community Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/rollingafull/labtomation/issues)
- **Discussions**: [Ask questions and share ideas](https://github.com/rollingafull/labtomation/discussions)
- **Documentation**: [Read the guides](setup/README.md)

### Commercial Support

For enterprise deployments, custom development, or professional support, please contact:

**Email**: <rolling@a-full.com>

## 🌟 Acknowledgments

Labtomation builds upon the excellent work of many open-source projects:

- [Proxmox VE](https://www.proxmox.com/) - Virtualization platform
- [Ansible](https://www.ansible.com/) - Configuration management
- [Terraform](https://www.terraform.io/) - Infrastructure as code
- [HashiCorp Vault](https://www.vaultproject.io/) - Secrets management
- [Jenkins](https://www.jenkins.io/) - Automation server
- [Rocky Linux](https://rockylinux.org/) - Enterprise Linux distribution

## 📊 Project Stats

![GitHub stars](https://img.shields.io/github/stars/rollingafull/labtomation?style=social)
![GitHub forks](https://img.shields.io/github/forks/rollingafull/labtomation?style=social)
![GitHub issues](https://img.shields.io/github/issues/rollingafull/labtomation)
![GitHub pull requests](https://img.shields.io/github/issues-pr/rollingafull/labtomation)

<div align="center">

**Made with ❤️ for the homelab community**

[Installation Guide](setup/README.md) • [Report Bug](https://github.com/rollingafull/labtomation/issues) • [Request Feature](https://github.com/rollingafull/labtomation/issues)

</div>
