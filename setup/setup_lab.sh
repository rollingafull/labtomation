#!/bin/bash
# shellcheck source=/dev/null

#===============================================================================
# Title: Minimal Lab Setup Script
# Description: Installs Ansible and Python - DevOps tools via Ansible playbooks
#-------------------------------------------------------------------------------
# Author: rolling (rolling@a-full.com)
# Created: 2025-10-04
# Updated: 2025-10-23
# Version: 1.0.0 - First Stable Release
#-------------------------------------------------------------------------------
# Dependencies: None (installs what's needed)
#-------------------------------------------------------------------------------
# Usage: ./setup_lab.sh [OPTIONS]
#
# Options:
#   --install-only        Install Ansible + Python only (default mode)
#   -h, --help            Show this help message
#
# This script:
#   1. Detects OS type (Rocky, Debian, Ubuntu)
#   2. Updates system packages
#   3. Installs Ansible
#   4. Installs Python 3 + pip
#   5. Installs required Python packages
#
# DevOps tools (Terraform, Vault, Jenkins) are installed via Ansible playbooks
# See: playbooks/setup_devops_tools.yml
#
# Notes:
#   - Requires root/sudo access
#   - Idempotent - safe to run multiple times
#   - Minimal dependencies by design
#===============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library for logging
source "$SCRIPT_DIR/common_lib.sh"

# Error handling
set -euo pipefail

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

OS_TYPE=""
OS_VERSION=""

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: show_help
#-------------------------------------------------------------------------------
show_help() {
    grep '^#' "$0" | grep -E '^#($|[^!])' | sed 's/^# \?//'
    exit 0
}

#-------------------------------------------------------------------------------
# Function: parse_arguments
#-------------------------------------------------------------------------------
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Function: detect_os
# Description: Detects operating system type and version
#-------------------------------------------------------------------------------
detect_os() {
    log_step "Detecting operating system" "INFO"

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_TYPE="${ID}"
        OS_VERSION="${VERSION_ID}"
    else
        log_step "Cannot detect OS - /etc/os-release not found" "FAILED"
        exit 1
    fi

    log_step "Detected OS: ${OS_TYPE} ${OS_VERSION}" "SUCCESS"
}

#-------------------------------------------------------------------------------
# Function: update_system
# Description: Updates system packages
#-------------------------------------------------------------------------------
update_system() {
    log_step "Updating system packages" "INFO"

    case "$OS_TYPE" in
        rocky|rhel|centos|fedora|almalinux)
            sudo dnf check-update || true
            log_step "System package cache updated" "SUCCESS"
            ;;
        ubuntu|debian)
            sudo apt-get update -qq
            log_step "System package cache updated" "SUCCESS"
            ;;
        *)
            log_step "Unsupported OS: $OS_TYPE" "FAILED"
            exit 1
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Function: install_ansible
# Description: Installs Ansible package
#-------------------------------------------------------------------------------
install_ansible() {
    # Check if already installed
    if command -v ansible &>/dev/null; then
        local ansible_version
        ansible_version=$(ansible --version | head -n1)
        log_step "Ansible already installed: $ansible_version" "SKIP"
        return 0
    fi

    log_step "Installing Ansible" "INFO"

    case "$OS_TYPE" in
        rocky|rhel|centos|almalinux)
            # For Rocky/RHEL 9+, use ansible-core from AppStream
            # For older versions, try EPEL
            if [ "${OS_VERSION%%.*}" -ge 9 ]; then
                log_step "Installing ansible-core from AppStream (Rocky/RHEL ${OS_VERSION%%.*}+)" "INFO"
                sudo dnf install -y ansible-core
            else
                # Install EPEL repository for older versions
                if ! rpm -q epel-release &>/dev/null; then
                    log_step "Installing EPEL repository" "INFO"
                    sudo dnf install -y epel-release
                fi
                sudo dnf install -y ansible
            fi
            ;;
        fedora)
            sudo dnf install -y ansible
            ;;
        ubuntu|debian)
            sudo apt-get install -y ansible
            ;;
        *)
            log_step "Unsupported OS for Ansible installation: $OS_TYPE" "FAILED"
            exit 1
            ;;
    esac

    # Verify installation
    if command -v ansible &>/dev/null; then
        local ansible_version
        ansible_version=$(ansible --version | head -n1)
        log_step "Ansible installed: $ansible_version" "SUCCESS"
    else
        log_step "Ansible installation failed" "FAILED"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Function: install_python
# Description: Installs Python 3 and pip
#-------------------------------------------------------------------------------
install_python() {
    # Check if Python 3 is installed
    if command -v python3 &>/dev/null; then
        local python_version
        python_version=$(python3 --version)
        log_step "Python already installed: $python_version" "SKIP"
    else
        log_step "Installing Python 3" "INFO"

        case "$OS_TYPE" in
            rocky|rhel|centos|fedora|almalinux)
                sudo dnf install -y python3
                ;;
            ubuntu|debian)
                sudo apt-get install -y python3
                ;;
        esac

        log_step "Python 3 installed" "SUCCESS"
    fi

    # Check if pip is installed
    if command -v pip3 &>/dev/null; then
        local pip_version
        pip_version=$(pip3 --version)
        log_step "pip already installed: $pip_version" "SKIP"
    else
        log_step "Installing pip" "INFO"

        case "$OS_TYPE" in
            rocky|rhel|centos|fedora|almalinux)
                sudo dnf install -y python3-pip
                ;;
            ubuntu|debian)
                sudo apt-get install -y python3-pip
                ;;
        esac

        log_step "pip installed" "SUCCESS"
    fi
}

#-------------------------------------------------------------------------------
# Function: install_python_packages
# Description: Installs required Python packages for Ansible
#-------------------------------------------------------------------------------
install_python_packages() {
    log_step "Installing Python packages" "INFO"

    local packages=(
        "jmespath"      # For Ansible json_query filter
        "netaddr"       # For Ansible network filters
    )

    for package in "${packages[@]}"; do
        if python3 -c "import ${package//-/_}" &>/dev/null; then
            log_step "Python package already installed: $package" "SKIP"
        else
            log_step "Installing Python package: $package" "INFO"
            pip3 install --user "$package" || {
                log_step "Failed to install $package (non-critical)" "WARN"
            }
        fi
    done

    log_step "Python packages configured" "SUCCESS"
}

#-------------------------------------------------------------------------------
# Function: verify_installations
# Description: Verifies that all required tools are installed
#-------------------------------------------------------------------------------
verify_installations() {
    log_step "Verifying installations" "INFO"
    local failed=0

    echo ""
    echo "Installation verification:"
    echo ""

    # Check Ansible
    if command -v ansible &>/dev/null; then
        echo "✓ Ansible: $(ansible --version | head -1)"
    else
        echo "✗ Ansible not found"
        failed=$((failed + 1))
    fi

    # Check Python
    if command -v python3 &>/dev/null; then
        echo "✓ Python: $(python3 --version)"
    else
        echo "✗ Python not found"
        failed=$((failed + 1))
    fi

    # Check pip
    if command -v pip3 &>/dev/null; then
        echo "✓ pip: $(pip3 --version | cut -d' ' -f1,2)"
    else
        echo "✗ pip not found"
        failed=$((failed + 1))
    fi

    echo ""

    if [ $failed -eq 0 ]; then
        log_step "All tools verified successfully" "SUCCESS"
        return 0
    else
        log_step "$failed tool(s) failed verification" "FAILED"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: error_handler
# Description: Handles script errors
#-------------------------------------------------------------------------------
error_handler() {
    local line=$1
    local exit_code=$2
    log_step "Error on line $line (exit code: $exit_code)" "FAILED"
    echo ""
    echo "=========================================="
    echo "Setup failed. Check logs for details."
    echo "=========================================="
    exit "$exit_code"
}

trap 'error_handler ${LINENO} $?' ERR

#-------------------------------------------------------------------------------
# MAIN FUNCTION
#-------------------------------------------------------------------------------

main() {
    # Setup logging
    setup_logging "setup_lab"

    echo ""
    echo "=========================================="
    echo "Lab Setup Script v1.0.0"
    echo "Minimal Installation: Ansible + Python"
    echo "=========================================="
    echo ""

    # Parse arguments
    parse_arguments "$@"

    # Detect OS
    detect_os

    # Update system
    update_system

    # Install Ansible
    install_ansible

    # Install Python
    install_python

    # Install Python packages
    install_python_packages

    # Verify installations
    if ! verify_installations; then
        exit 1
    fi

    # Summary
    echo ""
    echo "=========================================="
    echo "✅ Minimal Setup Completed Successfully"
    echo "=========================================="
    echo ""
    echo "Installed:"
    echo "  - Ansible"
    echo "  - Python 3 + pip"
    echo "  - Python packages (jmespath, netaddr)"
    echo ""
    echo "Next Steps:"
    echo "  1. DevOps tools are installed via Ansible playbooks"
    echo "  2. Run: ansible-playbook playbooks/setup_devops_tools.yml"
    echo ""
    echo "Available playbook tags:"
    echo "  --tags terraform    Install only Terraform"
    echo "  --tags vault        Install only HashiCorp Vault"
    echo "  --tags jenkins      Install only Jenkins"
    echo "  --skip-tags jenkins Skip Jenkins installation"
    echo ""
    echo "=========================================="
    echo ""

    log_step "Setup completed successfully" "SUCCESS"
    return 0
}

#-------------------------------------------------------------------------------
# ENTRY POINT
#-------------------------------------------------------------------------------

main "$@"
exit 0
