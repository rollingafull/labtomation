#!/bin/bash
#===============================================================================
# Script: Update Labtomation VM Playbooks
# Description: Syncs updated playbooks to the Labtomation VM
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#-------------------------------------------------------------------------------
# Functions
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

show_usage() {
    cat << EOF
Usage: $0 <VM_IP> [SSH_KEY]

Updates playbooks on the Labtomation VM with local changes.

Arguments:
  VM_IP      IP address of the Labtomation VM
  SSH_KEY    Path to SSH key (default: ~/.ssh/lab_id_ed25519)

Examples:
  $0 192.168.1.100
  $0 192.168.1.100 /path/to/ssh_key

EOF
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

# Check arguments
if [[ $# -lt 1 ]]; then
    log_error "Missing required argument: VM_IP"
    echo
    show_usage
    exit 1
fi

VM_IP="$1"
SSH_KEY="${2:-$HOME/.ssh/lab_id_ed25519}"

# Verify SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
    log_error "SSH key not found: $SSH_KEY"
    exit 1
fi

# Verify playbooks directory exists
PLAYBOOKS_DIR="$SCRIPT_DIR/playbooks"
if [[ ! -d "$PLAYBOOKS_DIR" ]]; then
    log_error "Playbooks directory not found: $PLAYBOOKS_DIR"
    exit 1
fi

log_info "Updating playbooks on Labtomation VM at $VM_IP"
echo

# Test SSH connection
log_info "Testing SSH connection..."
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY" "labtomation@${VM_IP}" "echo 'Connection OK'" &>/dev/null; then
    log_error "Cannot connect to VM at $VM_IP"
    exit 1
fi
log_success "SSH connection established"

# Backup existing playbooks
log_info "Creating backup of existing playbooks..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "labtomation@${VM_IP}" \
    "if [ -d /opt/labtomation/playbooks ]; then sudo cp -r /opt/labtomation/playbooks /opt/labtomation/playbooks.backup.\$(date +%Y%m%d_%H%M%S); fi"
log_success "Backup created"

# Copy updated playbooks
log_info "Copying updated playbooks..."
rsync -avz --delete \
    -e "ssh -o StrictHostKeyChecking=no -i $SSH_KEY" \
    "$PLAYBOOKS_DIR/" \
    "labtomation@${VM_IP}:/tmp/playbooks_update/"

# Move playbooks to final location
log_info "Installing updated playbooks..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "labtomation@${VM_IP}" << 'EOSSH'
    sudo rm -rf /opt/labtomation/playbooks
    sudo mv /tmp/playbooks_update /opt/labtomation/playbooks
    sudo chown -R labtomation:labtomation /opt/labtomation/playbooks
    sudo chmod -R u+rwX,go+rX /opt/labtomation/playbooks
EOSSH
log_success "Playbooks updated successfully"

# Verify installation
log_info "Verifying installation..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "labtomation@${VM_IP}" \
    "ls -la /opt/labtomation/playbooks/requirements.yml" &>/dev/null
log_success "Verification passed"

echo
log_success "Playbooks updated successfully on VM at $VM_IP"
echo
log_info "You can now run the bootstrap from inside the VM:"
echo -e "  ${YELLOW}ssh -i $SSH_KEY labtomation@${VM_IP}${NC}"
echo -e "  ${YELLOW}cd /opt/labtomation/playbooks${NC}"
echo -e "  ${YELLOW}ansible-playbook bootstrap_proxmox_cluster.yml${NC}"
echo
