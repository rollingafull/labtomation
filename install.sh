#!/bin/bash
# shellcheck disable=SC2181

#===============================================================================
# Title: Labtomation Quick Installer
# Description: Clone, install, and cleanup Labtomation from GitHub
#-------------------------------------------------------------------------------
# Author: rolling (rolling@a-full.com)
# Created: 2025-10-23
# Version: 1.0.1
#===============================================================================
#
# OVERVIEW:
#   This script automates the complete Labtomation installation:
#   1. Creates temporary directory 'labtomation' in current location
#   2. Clones the repository from GitHub
#   3. Executes the labtomation.sh script to create and configure VM
#   4. Copies SSH keys from setup/ to current directory
#   5. Cleans up all temporary files (keys are preserved in current directory)
#
# USAGE:
#   curl -fsSL https://raw.githubusercontent.com/rollingafull/labtomation/main/install.sh | bash
#
#   Or download and run locally:
#   wget https://raw.githubusercontent.com/rollingafull/labtomation/main/install.sh
#   chmod +x install.sh
#   ./install.sh [OPTIONS]
#
# OPTIONS:
#   All options are passed directly to labtomation.sh:
#   --vmid <id>         VM ID (default: auto-generate)
#   --name <name>       VM name (default: labtomation)
#   --os <os>           OS: rocky10, debian13, ubuntu2404
#   --cores <num>       CPU cores (default: 2)
#   --memory <mb>       Memory in MB (default: 8192)
#   --disk <gb>         Disk size in GB (default: 32)
#   --storage <name>    Storage name (default: auto-detect)
#   --force             Force recreate VM if exists
#
# EXAMPLES:
#   # Interactive mode
#   ./install.sh
#
#   # Rocky Linux with defaults
#   ./install.sh --os rocky10
#
#   # Custom configuration
#   ./install.sh --os rocky10 --cores 4 --memory 16384 --disk 50
#
# NOTES:
#   - Requires git to be installed on Proxmox host
#   - SSH keys (id_ed25519) are copied to current directory after installation
#   - Keys are needed to SSH into the created VM
#   - Cleanup happens automatically after successful installation
#   - If installation fails, directory is preserved for debugging
#
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

GITHUB_REPO="https://github.com/rollingafull/labtomation.git"
INSTALL_DIR="labtomation"
SSH_KEY_NAME="id_ed25519"

#-------------------------------------------------------------------------------
# COLORS AND FORMATTING
#-------------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

#-------------------------------------------------------------------------------
# HELPER FUNCTIONS
#-------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_step() {
    echo -e "${CYAN}▶${NC} ${BOLD}$1${NC}"
}

log_header() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

check_command() {
    local cmd="$1"

    if ! command -v "$cmd" &> /dev/null; then
        case "$cmd" in
            git)
                log_warning "Git is not installed on this Proxmox VE node"
                echo ""

                # Try to read from terminal even if stdin is piped (curl | bash)
                # Using /dev/tty allows interactive input even in pipe mode
                if [ -c /dev/tty ]; then
                    # Terminal available - ask user interactively
                    read -rp "Do you want to install git now? (y/N): " response </dev/tty
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        log_step "Installing git..."
                        if apt-get update &> /dev/null && apt-get install -y git &> /dev/null; then
                            log_success "Git installed successfully"
                        else
                            log_error "Failed to install git"
                            log_error "Please install git manually: apt-get install git"
                            exit 1
                        fi
                    else
                        log_error "Git is required to clone the repository"
                        log_error "Please install it manually: apt-get install git"
                        exit 1
                    fi
                else
                    # No terminal available (truly non-interactive, e.g., cron/automation)
                    log_error "Git is required to clone the repository"
                    log_error "Please install it manually: apt-get install git"
                    log_error "Or run this script with terminal access"
                    exit 1
                fi
                ;;
            qm|pvesh)
                log_error "Command '$cmd' not found"
                echo ""
                log_error "This script must be run on a Proxmox VE node as root."
                log_error "Requirements:"
                log_error "  1. Must be executed on a Proxmox VE server"
                log_error "  2. Proxmox VE must be properly installed and configured"
                log_error "  3. Run as root or with sudo privileges"
                echo ""
                log_error "If Proxmox VE is installed, try running with sudo:"
                log_error "  sudo $0"
                exit 1
                ;;
            *)
                log_error "Required command '$cmd' not found. Please install it first."
                exit 1
                ;;
        esac
    fi
}

#-------------------------------------------------------------------------------
# PRE-FLIGHT CHECKS
#-------------------------------------------------------------------------------

log_header "LABTOMATION QUICK INSTALLER"

log_step "Running pre-flight checks..."

# Check if running on Proxmox
if [ ! -f /etc/pve/.version ]; then
    log_error "This script must be run on a Proxmox VE server"
    exit 1
fi
log_success "Running on Proxmox VE"

# Check required commands
check_command git
check_command qm
check_command pvesh
log_success "Required commands available"

# Check if install directory already exists
if [ -d "$INSTALL_DIR" ]; then
    log_warning "Directory '$INSTALL_DIR' already exists in current location"
    read -rp "Do you want to remove it and continue? (y/N): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_info "Removing existing directory..."
        rm -rf "$INSTALL_DIR"
        log_success "Directory removed"
    else
        log_error "Installation cancelled by user"
        exit 1
    fi
fi

#-------------------------------------------------------------------------------
# CLONE REPOSITORY
#-------------------------------------------------------------------------------

log_header "CLONING REPOSITORY"

log_step "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
log_success "Directory created"

log_step "Cloning Labtomation repository from GitHub..."
if git clone "$GITHUB_REPO" "$INSTALL_DIR" > /dev/null 2>&1; then
    log_success "Repository cloned successfully"
else
    log_error "Failed to clone repository"
    log_error "Please check your internet connection and try again"
    rm -rf "$INSTALL_DIR"
    exit 1
fi

#-------------------------------------------------------------------------------
# EXECUTE INSTALLATION
#-------------------------------------------------------------------------------

log_header "RUNNING LABTOMATION SETUP"

log_step "Changing to setup directory..."
cd "$INSTALL_DIR/setup" || {
    log_error "Failed to change to setup directory"
    exit 1
}

log_step "Making labtomation.sh executable..."
chmod +x labtomation.sh

log_info "Starting Labtomation setup script..."
log_info "All arguments will be passed to labtomation.sh: $*"
echo ""

# Execute labtomation.sh with all passed arguments
if ./labtomation.sh "$@"; then
    INSTALL_SUCCESS=true
    log_success "Labtomation setup completed successfully!"
else
    INSTALL_SUCCESS=false
    log_error "Labtomation setup failed!"
    log_warning "Installation directory preserved for debugging: $(pwd)/.."
fi

# Return to parent directory
cd ../..

#-------------------------------------------------------------------------------
# PRESERVE SSH KEYS
#-------------------------------------------------------------------------------

if [ "$INSTALL_SUCCESS" = true ]; then
    log_header "PRESERVING SSH KEYS"

    SSH_KEY_PRIVATE="$INSTALL_DIR/setup/$SSH_KEY_NAME"
    SSH_KEY_PUBLIC="${SSH_KEY_PRIVATE}.pub"
    SAVED_KEY_DIR="$(pwd)"

    if [ -f "$SSH_KEY_PRIVATE" ] && [ -f "$SSH_KEY_PUBLIC" ]; then
        log_step "Moving SSH keys to current directory..."

        # Copy keys to current directory (where install.sh was executed)
        cp "$SSH_KEY_PRIVATE" "$SAVED_KEY_DIR/$SSH_KEY_NAME"
        cp "$SSH_KEY_PUBLIC" "$SAVED_KEY_DIR/${SSH_KEY_NAME}.pub"

        # Set proper permissions
        chmod 600 "$SAVED_KEY_DIR/$SSH_KEY_NAME"
        chmod 644 "$SAVED_KEY_DIR/${SSH_KEY_NAME}.pub"

        log_success "SSH keys preserved in current directory"
        log_info "Private key: $SAVED_KEY_DIR/$SSH_KEY_NAME"
        log_info "Public key:  $SAVED_KEY_DIR/${SSH_KEY_NAME}.pub"
    else
        log_warning "SSH keys not found in $INSTALL_DIR/setup/"
        log_warning "This may indicate an installation issue"
    fi
fi

#-------------------------------------------------------------------------------
# CLEANUP
#-------------------------------------------------------------------------------

if [ "$INSTALL_SUCCESS" = true ]; then
    log_header "CLEANUP"

    log_step "Removing temporary installation directory..."
    if rm -rf "$INSTALL_DIR"; then
        log_success "Cleanup completed"
        log_success "Temporary files removed (SSH keys preserved)"
    else
        log_warning "Could not remove installation directory: $INSTALL_DIR"
        log_info "You can safely remove it manually: rm -rf $INSTALL_DIR"
    fi
fi

#-------------------------------------------------------------------------------
# FINAL SUMMARY
#-------------------------------------------------------------------------------

log_header "INSTALLATION SUMMARY"

if [ "$INSTALL_SUCCESS" = true ]; then
    echo -e "${GREEN}${BOLD}✓ Installation completed successfully!${NC}"
    echo ""
    echo "SSH Keys preserved in current directory:"
    echo "  • Private: $(pwd)/$SSH_KEY_NAME"
    echo "  • Public:  $(pwd)/${SSH_KEY_NAME}.pub"
    echo ""
    echo "Next steps:"
    echo "  1. Note your VM IP address from the output above"
    echo "  2. SSH into your VM: ssh -i $(pwd)/$SSH_KEY_NAME labtomation@<vm-ip>"
    echo "  3. Access services:"
    echo "     • Vault:   http://<vm-ip>:8200"
    echo "     • Jenkins: http://<vm-ip>:8080"
    echo ""
    echo "IMPORTANT: Keep the SSH keys in a safe location!"
    echo "  You need them to access your VM."
    echo ""
    echo "For more information, visit:"
    echo "  https://github.com/rollingafull/labtomation"
    echo ""
else
    echo -e "${RED}${BOLD}✗ Installation failed!${NC}"
    echo ""
    echo "Installation directory preserved for debugging:"
    echo "  $INSTALL_DIR"
    echo ""
    echo "Check the error messages above for details."
    echo "For help, visit: https://github.com/rollingafull/labtomation/issues"
    echo ""
    exit 1
fi

log_header "DONE"
