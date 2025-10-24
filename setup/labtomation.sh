#!/bin/bash
# shellcheck source=/dev/null

#===============================================================================
# Title: Proxmox VE Lab Automation Script
# Description: Creates a VM and configures it as a complete DevOps lab
#-------------------------------------------------------------------------------
# Author: rolling (rolling@a-full.com)
# Created: 2025-10-04
# Updated: 2025-10-23
# Version: 1.0.0 - First Stable Release
#===============================================================================
#
# OVERVIEW:
#   This script automates the complete setup of a DevOps lab VM on Proxmox:
#   1. Downloads cloud-init OS image (Rocky 10, Debian 13, Ubuntu 24.04)
#   2. Creates VM with modern Q35 + EFI configuration
#   3. Imports and resizes disk to requested size
#   4. Configures cloud-init with SSH keys
#   5. Starts VM and waits for network
#   6. Installs Ansible + Python via Bash
#   7. Runs Ansible playbooks to install:
#      - Terraform
#      - HashiCorp Vault
#      - Jenkins
#      - Common development tools (git, vim, btop, curl, etc.)
#   8. Adds service tags to VM (OS + services)
#
# USAGE:
#   ./labtomation.sh [OPTIONS]
#
# OPTIONS:
#   --vmid <id>         VM ID (default: auto-generate from cluster)
#   --name <name>       VM name (default: labtomation)
#   --os <os>           OS: rocky10, debian13, ubuntu2404 (default: interactive)
#   --cores <num>       CPU cores (default: 2)
#   --memory <mb>       Memory in MB (default: 8192)
#   --disk <gb>         Disk size in GB (default: 32)
#   --storage <name>    Storage name (default: auto-detect)
#   --force             Force recreate VM if it already exists
#   -h, --help          Show this help message
#
# EXAMPLES:
#   # Interactive mode
#   ./labtomation.sh
#
#   # CLI mode with defaults
#   ./labtomation.sh --os rocky10
#
#   # Custom configuration
#   ./labtomation.sh --name devops-lab --os ubuntu2404 --cores 4 --memory 8192
#
# REQUIREMENTS:
#   - Proxmox VE 7.0+ (for Q35+EFI support)
#   - Internet access (for downloading OS images)
#   - Storage: 10GB+ free space
#   - Tools: qm, pvesh, jq, wget
#
# NOTES:
#   - Works with both standalone and clustered Proxmox
#   - Auto-detects best available storage
#   - Generates SSH keys automatically if not present
#   - Safe to run multiple times (idempotent where possible)
#
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# INITIALIZATION
#-------------------------------------------------------------------------------

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$SCRIPT_DIR/common_lib.sh"
source "$SCRIPT_DIR/vm_lib.sh"

# Setup logging
setup_logging "labtomation"

#-------------------------------------------------------------------------------
# DEFAULT CONFIGURATION
#-------------------------------------------------------------------------------

VMID=""
VM_NAME="labtomation"
OS_KEY=""
CPU_CORES="2"
MEMORY="8192"
DISK_SIZE="32"
STORAGE=""
FORCE_RECREATE=0

#-------------------------------------------------------------------------------
# HELPER FUNCTIONS
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: show_help
# Description: Displays usage information
#-------------------------------------------------------------------------------
show_help() {
    grep '^#' "$0" | grep -E '^#($|[^!])' | sed 's/^# \?//'
    exit 0
}

#-------------------------------------------------------------------------------
# Function: parse_arguments
# Description: Parses command line arguments
#-------------------------------------------------------------------------------
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vmid)
                VMID="$2"
                shift 2
                ;;
            --name)
                VM_NAME="$2"
                shift 2
                ;;
            --os)
                OS_KEY="$2"
                shift 2
                ;;
            --cores)
                CPU_CORES="$2"
                shift 2
                ;;
            --memory)
                MEMORY="$2"
                shift 2
                ;;
            --disk)
                DISK_SIZE="$2"
                shift 2
                ;;
            --storage)
                STORAGE="$2"
                shift 2
                ;;
            --force)
                FORCE_RECREATE=1
                shift
                ;;
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
# Function: select_os_interactive
# Description: Interactive OS selection menu
#-------------------------------------------------------------------------------
select_os_interactive() {
    local os_options=("rocky10" "debian13" "ubuntu2404")
    local os_display=()

    # Get display names from configuration
    for os in "${os_options[@]}"; do
        local display_name
        display_name=$(get_os_config "$os" "display_name")
        if [[ -z "$display_name" ]]; then
            display_name="$os"
        fi
        os_display+=("$display_name")
    done

    echo ""
    echo "Select Operating System:"
    for i in "${!os_display[@]}"; do
        echo "$((i+1))) ${os_display[$i]}"
    done
    echo ""

    # Read user selection
    while true; do
        read -rp "Enter choice [1-3] (default=1): " choice

        if [[ -z "$choice" ]]; then
            choice=1
        fi

        if [[ "$choice" =~ ^[1-3]$ ]]; then
            OS_KEY="${os_options[$((choice-1))]}"
            selected_name="${os_display[$((choice-1))]}"
            log_step "Selected OS: $selected_name" "INFO"
            break
        else
            echo "Invalid selection. Please choose 1-3 or press ENTER for default"
        fi
    done
}

#-------------------------------------------------------------------------------
# Function: setup_ssh_keys
# Description: Ensures SSH keys exist, generates if needed
# Returns: Path to private key on stdout
#-------------------------------------------------------------------------------
setup_ssh_keys() {
    local ssh_key="$SCRIPT_DIR/id_ed25519"

    # Check for existing SSH keys
    if [ -f "${ssh_key}.pub" ] && [ -f "$ssh_key" ]; then
        log_step "Using existing SSH key: ${ssh_key}" "INFO" >&2
    else
        log_step "Generating new SSH key" "INFO" >&2
        ssh-keygen -t ed25519 -f "$ssh_key" -N "" -C "labtomation@proxmox"
        chmod 600 "$ssh_key"
        chmod 644 "${ssh_key}.pub"
        log_step "SSH key generated: ${ssh_key}" "SUCCESS" >&2
    fi

    echo "$ssh_key"
}

#-------------------------------------------------------------------------------
# MAIN FUNCTION
#-------------------------------------------------------------------------------

main() {
    log_header "Labtomation v2.1.0 - Proxmox Lab Automation"

    # Parse command line arguments
    parse_arguments "$@"

    # Interactive OS selection if not provided via CLI
    if [ -z "$OS_KEY" ]; then
        select_os_interactive
    fi

    #---------------------------------------------------------------------------
    # VALIDATE AND PREPARE
    #---------------------------------------------------------------------------

    # Export force recreate flag for vm_lib.sh functions
    export VM_FORCE_RECREATE="$FORCE_RECREATE"

    # Auto-generate VMID if not provided
    if [ -z "$VMID" ]; then
        VMID=$(generate_vmid)
        log_step "Auto-generated VMID: $VMID" "INFO"
    fi

    # Validate VMID is available (unless force recreate is enabled)
    if ! validate_vmid "$VMID"; then
        if [ "$FORCE_RECREATE" -eq 1 ]; then
            log_step "VMID $VMID already exists, will be recreated (--force enabled)" "WARN"
        else
            log_step "VMID $VMID already exists. Use --force to recreate or run idempotently" "INFO"
            # Continue anyway - idempotent mode
        fi
    fi

    # Get OS configuration
    local os_display os_user os_url os_file
    os_display=$(get_os_config "$OS_KEY" "display_name")
    os_user=$(get_os_config "$OS_KEY" "default_user")
    os_url=$(get_os_config "$OS_KEY" "vm_url")
    os_file=$(get_os_config "$OS_KEY" "vm_file")

    if [ -z "$os_display" ]; then
        log_step "Invalid OS key: $OS_KEY" "FAILED"
        exit 1
    fi

    # Auto-detect storage if not provided
    if [ -z "$STORAGE" ]; then
        STORAGE=$(get_storage_for_vm 2>/dev/null)
        if [ -z "$STORAGE" ]; then
            log_step "Could not detect suitable storage" "FAILED"
            exit 1
        fi
    fi

    # Setup SSH keys
    local ssh_key
    ssh_key=$(setup_ssh_keys)

    #---------------------------------------------------------------------------
    # DISPLAY CONFIGURATION AND CONFIRM
    #---------------------------------------------------------------------------

    echo ""
    echo "=========================================="
    echo "VM Configuration"
    echo "=========================================="
    echo "VMID:     $VMID"
    echo "Name:     $VM_NAME"
    echo "OS:       $os_display"
    echo "CPU:      $CPU_CORES cores"
    echo "Memory:   ${MEMORY}MB"
    echo "Disk:     ${DISK_SIZE}GB"
    echo "Storage:  $STORAGE"
    echo "=========================================="
    echo ""

    read -rp "Continue with VM creation? [Y/n]: " confirm
    echo ""

    if [[ "$confirm" =~ ^[Nn] ]]; then
        log_step "Aborted by user" "INFO"
        exit 0
    fi

    #---------------------------------------------------------------------------
    # STEP 1: Download OS Image
    #---------------------------------------------------------------------------

    echo ""
    echo "=========================================="
    log_step "STEP 1: Downloading OS Image" "START"
    echo "=========================================="

    cd "$SCRIPT_DIR"

    if [ ! -f "$os_file" ]; then
        log_step "Downloading $os_url" "INFO"
        wget -O "$os_file" "$os_url"
        log_step "Download completed" "SUCCESS"
    else
        log_step "Image already exists: $os_file" "SKIP"
    fi

    #---------------------------------------------------------------------------
    # STEP 2: Create VM
    #---------------------------------------------------------------------------

    echo ""
    echo "=========================================="
    log_step "STEP 2: Creating VM" "START"
    echo "=========================================="

    # Create VM using modular function (pass OS_KEY for OS-specific adjustments)
    if ! create_vm "$VMID" "$VM_NAME" "$CPU_CORES" "$MEMORY" "$STORAGE" "$OS_KEY"; then
        log_step "Failed to create VM" "FAILED"
        exit 1
    fi

    # Import and configure disk
    if ! import_disk "$VMID" "$os_file" "$STORAGE" "$DISK_SIZE"; then
        log_step "Failed to import disk" "FAILED"
        exit 1
    fi

    # Configure boot and cloud-init drive
    if ! configure_vm_boot "$VMID" "$STORAGE"; then
        log_step "Failed to configure boot" "FAILED"
        exit 1
    fi

    #---------------------------------------------------------------------------
    # STEP 3: Configure Cloud-Init
    #---------------------------------------------------------------------------

    echo ""
    echo "=========================================="
    log_step "STEP 3: Configuring Cloud-Init" "START"
    echo "=========================================="

    if ! configure_cloud_init "$VMID" "$os_user" "${ssh_key}.pub"; then
        log_step "Failed to configure cloud-init" "FAILED"
        exit 1
    fi

    #---------------------------------------------------------------------------
    # STEP 4: Start VM and Wait for Network
    #---------------------------------------------------------------------------

    echo ""
    echo "=========================================="
    log_step "STEP 4: Starting VM" "START"
    echo "=========================================="

    # Check if VM is already running
    local vm_status
    vm_status=$(qm status "$VMID" 2>/dev/null | awk '{print $2}')

    if [ "$vm_status" = "running" ]; then
        log_step "VM is already running" "SKIP"
    else
        qm start "$VMID"
        log_step "VM started" "SUCCESS"
    fi

    local vm_ip
    vm_ip=$(wait_for_vm_ip "$VMID" 300)

    if [ -z "$vm_ip" ]; then
        log_step "Failed to get VM IP" "FAILED"
        exit 1
    fi

    log_step "VM is ready at IP: $vm_ip" "SUCCESS"

    #---------------------------------------------------------------------------
    # STEP 5: Wait for SSH Access
    #---------------------------------------------------------------------------

    echo ""
    echo "=========================================="
    log_step "STEP 5: Waiting for SSH Access" "START"
    echo "=========================================="

    if ! wait_for_ssh "$vm_ip" "$os_user" "$ssh_key" 180; then
        log_step "Failed to establish SSH connection" "FAILED"
        exit 1
    fi

    # Wait for cloud-init to complete
    wait_for_cloud_init "$vm_ip" "$os_user" "$ssh_key"

    # Install qemu-guest-agent for future operations
    install_qemu_agent "$vm_ip" "$os_user" "$ssh_key"

    #---------------------------------------------------------------------------
    # STEP 6: Run Lab Setup Inside VM
    #---------------------------------------------------------------------------

    echo ""
    echo "=========================================="
    log_step "STEP 6: Configuring Lab Environment" "START"
    echo "=========================================="

    log_step "Copying setup scripts to VM" "INFO"

    # Create remote directories with proper permissions
    ssh -o StrictHostKeyChecking=no -i "$ssh_key" "${os_user}@${vm_ip}" \
        "sudo mkdir -p /opt/labtomation/config && sudo chown -R ${os_user}:${os_user} /opt/labtomation"

    # Copy setup scripts and libraries
    scp -o StrictHostKeyChecking=no -i "$ssh_key" \
        "$SCRIPT_DIR/setup_lab.sh" \
        "$SCRIPT_DIR/common_lib.sh" \
        "${os_user}@${vm_ip}:/opt/labtomation/"

    # Copy config files
    scp -o StrictHostKeyChecking=no -i "$ssh_key" \
        "$SCRIPT_DIR/config/"*.conf \
        "${os_user}@${vm_ip}:/opt/labtomation/config/"

    # Copy playbooks
    scp -r -o StrictHostKeyChecking=no -i "$ssh_key" \
        "$SCRIPT_DIR/playbooks" \
        "${os_user}@${vm_ip}:/opt/labtomation/"

    log_step "Scripts and playbooks copied successfully" "SUCCESS"

    # Execute setup_lab.sh to install Ansible + Python
    log_step "Installing Ansible and Python on VM" "INFO"

    ssh -o StrictHostKeyChecking=no -i "$ssh_key" "${os_user}@${vm_ip}" \
        "cd /opt/labtomation && chmod +x setup_lab.sh && ./setup_lab.sh"

    log_step "Ansible installed successfully" "SUCCESS"

    # Create Ansible inventory for localhost
    log_step "Creating Ansible inventory" "INFO"

    ssh -o StrictHostKeyChecking=no -i "$ssh_key" "${os_user}@${vm_ip}" \
        "cat > /opt/labtomation/playbooks/inventory/localhost.yml << 'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
EOF"

    # Execute Ansible playbook to install DevOps tools
    log_step "Running Ansible playbook for DevOps tools (this may take 10-15 minutes)" "INFO"

    ssh -o StrictHostKeyChecking=no -i "$ssh_key" "${os_user}@${vm_ip}" \
        "cd /opt/labtomation/playbooks && ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml"

    log_step "DevOps tools installed successfully" "SUCCESS"

    #---------------------------------------------------------------------------
    # STEP 7: Verification
    #---------------------------------------------------------------------------

    echo ""
    echo "=========================================="
    log_step "STEP 7: Verifying Installation" "START"
    echo "=========================================="

    if ssh -o StrictHostKeyChecking=no -i "$ssh_key" "${os_user}@${vm_ip}" "bash -s" <<'VERIFY_SCRIPT'
#!/bin/bash
failed=0

echo "Verifying installations..."
echo ""

# Check Ansible
if command -v ansible &>/dev/null; then
    echo "✓ Ansible: $(ansible --version | head -1)"
else
    echo "✗ Ansible not found"
    failed=$((failed + 1))
fi

# Check Terraform
if command -v terraform &>/dev/null; then
    echo "✓ Terraform: $(terraform version | head -1)"
else
    echo "✗ Terraform not found"
    failed=$((failed + 1))
fi

# Check Vault
if command -v vault &>/dev/null; then
    echo "✓ Vault: $(vault version | head -1)"

    # Check if Vault service is running
    if systemctl is-active --quiet vault; then
        echo "  └─ Vault service is running"
    else
        echo "  └─ Vault service is not running"
    fi
else
    echo "✗ Vault not found"
    failed=$((failed + 1))
fi

# Check Jenkins (optional)
if command -v jenkins &>/dev/null || systemctl list-units --type=service --all | grep -q jenkins; then
    echo "✓ Jenkins: Installed"
    if systemctl is-active --quiet jenkins; then
        echo "  └─ Jenkins service is running"
    fi
fi

echo ""
exit $failed
VERIFY_SCRIPT
    then
        log_step "All tools verified successfully" "SUCCESS"
    else
        log_step "Some tools failed verification" "WARN"
    fi

    #---------------------------------------------------------------------------
    # Add service tags to VM
    #---------------------------------------------------------------------------

    log_step "Adding service tags to VM" "INFO"
    add_vm_tag "$VMID" "ansible"
    add_vm_tag "$VMID" "terraform"
    add_vm_tag "$VMID" "vault"
    add_vm_tag "$VMID" "jenkins"
    log_step "Service tags added" "SUCCESS"

    #---------------------------------------------------------------------------
    # CLEANUP AND FINAL SUMMARY
    #---------------------------------------------------------------------------

    # Cleanup downloaded image
    if [ -f "$os_file" ]; then
        log_step "Cleaning up downloaded image" "INFO"
        rm -f "$os_file"
    fi

    echo ""
    echo "=========================================="
    echo "✅ Lab Setup Completed Successfully!"
    echo "=========================================="
    echo "VM ID:        $VMID"
    echo "VM Name:      $VM_NAME"
    echo "IP Address:   $vm_ip"
    echo "SSH User:     $os_user"
    echo "SSH Key:      $ssh_key"
    echo ""
    echo "Connect to VM:"
    echo "  ssh -i $ssh_key ${os_user}@${vm_ip}"
    echo ""
    echo "Installed Tools:"
    echo "  - Ansible + Python packages"
    echo "  - Terraform"
    echo "  - HashiCorp Vault (service running)"
    echo "  - Jenkins (optional, if enabled)"
    echo ""
    echo "Vault Access:"
    echo "  URL: http://$vm_ip:8200"
    echo "  Initialize: export VAULT_ADDR='http://127.0.0.1:8200' && vault operator init"
    echo ""
    echo "Next Steps:"
    echo "  1. Initialize Vault and save unseal keys"
    echo "  2. Configure Ansible playbooks for your infrastructure"
    echo "  3. Use Terraform for IaC deployments"
    echo ""
    echo "Ansible Playbooks:"
    echo "  Location: /opt/labtomation/playbooks"
    echo "  Re-run: cd /opt/labtomation/playbooks && ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml"
    echo "  Tags: --tags terraform,vault,jenkins"
    echo "=========================================="
    echo ""

    log_step "Setup completed successfully!" "SUCCESS"
}

#-------------------------------------------------------------------------------
# ERROR HANDLING
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
# ENTRY POINT
#-------------------------------------------------------------------------------

main "$@"
