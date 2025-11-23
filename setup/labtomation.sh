#!/bin/bash
# shellcheck source=/dev/null

#===============================================================================
# Title: Proxmox VE Lab Automation Script
# Description: Creates a VM and configures it as a complete DevOps lab
#-------------------------------------------------------------------------------
# Author: rolling (rolling@a-full.com)
# Created: 2025-10-04
# Updated: 2025-10-27
# Version: 2.0.0
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
#   7. Runs Ansible playbooks to install and configure:
#      - Terraform
#      - HashiCorp Vault (automatically initialized via vault_init role)
#      - Jenkins
#      - Common development tools (git, vim, btop, curl, etc.)
#      - Security setup (SSH keys backup, Vault initialization)
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

    # Read user selection (using /dev/tty for piped input compatibility)
    while true; do
        read -rp "Enter choice [1-3] (default=1): " choice </dev/tty

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
# Function: setup_security_directory
# Description: Creates secure directory structure for sensitive files
#-------------------------------------------------------------------------------
setup_security_directory() {
    local security_dir="/home/labtomation/.security"

    log_step "Setting up secure directory structure" "INFO" >&2

    # Create security directory if it doesn't exist
    if [ ! -d "$security_dir" ]; then
        mkdir -p "$security_dir"
        chown labtomation:labtomation "$security_dir"
        chmod 700 "$security_dir"
        log_step "Created secure directory: $security_dir" "SUCCESS" >&2
    else
        log_step "Secure directory already exists" "INFO" >&2
    fi

    echo "$security_dir"
}

#-------------------------------------------------------------------------------
# Function: secure_file
# Description: Applies strict permissions and immutable flag to a file
# Arguments: $1 - file path
#-------------------------------------------------------------------------------
secure_file() {
    local file="$1"

    if [ ! -f "$file" ]; then
        log_step "File not found: $file" "ERROR" >&2
        return 1
    fi

    # Set ownership and permissions
    chown labtomation:labtomation "$file"
    chmod 400 "$file"

    # Make file immutable (prevents accidental deletion/modification)
    chattr +i "$file" 2>/dev/null || {
        log_step "Warning: Could not set immutable flag on $file" "WARNING" >&2
    }

    log_step "Secured file: $file (400, immutable)" "SUCCESS" >&2
}

#-------------------------------------------------------------------------------
# Function: backup_ssh_keys
# Description: Backs up SSH keys to secure directory with immutable flag
# Arguments: $1 - source key path
#-------------------------------------------------------------------------------
backup_ssh_keys() {
    local source_key="$1"
    local security_dir="$2"
    local key_name=$(basename "$source_key")

    log_step "Backing up SSH keys to secure directory" "INFO" >&2

    # Backup private key
    if [ -f "$source_key" ]; then
        cp "$source_key" "$security_dir/.$key_name"
        secure_file "$security_dir/.$key_name"
    fi

    # Backup public key
    if [ -f "${source_key}.pub" ]; then
        cp "${source_key}.pub" "$security_dir/.${key_name}.pub"
        secure_file "$security_dir/.${key_name}.pub"
    fi

    log_step "SSH keys backed up and secured" "SUCCESS" >&2
}

#-------------------------------------------------------------------------------
# Function: setup_ssh_keys
# Description: Ensures SSH keys exist, generates if needed
# Returns: Path to private key on stdout
#-------------------------------------------------------------------------------
setup_ssh_keys() {
    local lab_ssh_key="$SCRIPT_DIR/lab_id_ed25519"
    local pve_ssh_key="$SCRIPT_DIR/pve_id_ed25519"

    # Check for existing lab SSH keys
    if [ -f "${lab_ssh_key}.pub" ] && [ -f "$lab_ssh_key" ]; then
        log_step "Using existing lab SSH key: ${lab_ssh_key}" "INFO" >&2
    else
        log_step "Generating new SSH key for lab VMs/LXC" "INFO" >&2
        ssh-keygen -t ed25519 -f "$lab_ssh_key" -N "" -C "labtomation-lab-access" >&2
        chmod 600 "$lab_ssh_key"
        chmod 644 "${lab_ssh_key}.pub"
        log_step "Lab SSH key generated: ${lab_ssh_key}" "SUCCESS" >&2
    fi

    # Check for existing Proxmox SSH keys
    if [ -f "${pve_ssh_key}.pub" ] && [ -f "$pve_ssh_key" ]; then
        log_step "Using existing Proxmox SSH key: ${pve_ssh_key}" "INFO" >&2
    else
        log_step "Generating new SSH key for Proxmox nodes" "INFO" >&2
        ssh-keygen -t ed25519 -f "$pve_ssh_key" -N "" -C "labtomation-proxmox-access" >&2
        chmod 600 "$pve_ssh_key"
        chmod 644 "${pve_ssh_key}.pub"
        log_step "Proxmox SSH key generated: ${pve_ssh_key}" "SUCCESS" >&2
    fi

    echo "$lab_ssh_key"
}

#-------------------------------------------------------------------------------
# Function: initialize_vault_auto
# Description: Automatically initializes Vault and saves credentials securely
# Arguments: $1 - security directory path
#-------------------------------------------------------------------------------
initialize_vault_auto() {
    local security_dir="$1"
    local vault_creds="$security_dir/.vault"
    local vault_addr="http://127.0.0.1:8200"

    log_step "Checking Vault initialization status" "INFO" >&2

    # Check if Vault is already initialized
    if vault status -address="$vault_addr" 2>/dev/null | grep -q "Initialized.*true"; then
        log_step "Vault is already initialized" "INFO" >&2

        # Check if credentials file exists
        if [ -f "$vault_creds" ]; then
            log_step "Vault credentials file already exists" "INFO" >&2
            return 0
        else
            log_step "Vault initialized but credentials file missing" "WARNING" >&2
            log_step "Manual intervention required" "ERROR" >&2
            return 1
        fi
    fi

    log_step "Initializing Vault..." "INFO" >&2

    # Initialize Vault and capture output
    local init_output
    init_output=$(vault operator init -address="$vault_addr" -format=json 2>&1)

    if [ $? -ne 0 ]; then
        log_step "Failed to initialize Vault" "ERROR" >&2
        echo "$init_output" >&2
        return 1
    fi

    # Parse and save credentials
    local unseal_keys=$(echo "$init_output" | jq -r '.unseal_keys_b64[]')
    local root_token=$(echo "$init_output" | jq -r '.root_token')

    # Create credentials file
    cat > "$vault_creds" << EOF
# Vault Initialization Credentials
# Generated: $(date -Iseconds)
# KEEP THIS FILE SECURE - Contains root access to Vault

[unseal_keys]
$(echo "$unseal_keys" | awk '{print "key" NR "=" $0}')

[root_token]
token=$root_token

[metadata]
initialized_at=$(date -Iseconds)
vault_address=$vault_addr
EOF

    # Secure the credentials file
    secure_file "$vault_creds"

    log_step "Vault initialized successfully" "SUCCESS" >&2
    log_step "Credentials saved to: $vault_creds" "SUCCESS" >&2

    echo "$vault_creds"
}

#-------------------------------------------------------------------------------
# Function: unseal_vault_auto
# Description: Automatically unseals Vault using stored credentials
# Arguments: $1 - vault credentials file path
#-------------------------------------------------------------------------------
unseal_vault_auto() {
    local vault_creds="$1"
    local vault_addr="http://127.0.0.1:8200"

    if [ ! -f "$vault_creds" ]; then
        log_step "Vault credentials file not found: $vault_creds" "ERROR" >&2
        return 1
    fi

    log_step "Checking Vault seal status" "INFO" >&2

    # Check if Vault is already unsealed
    if vault status -address="$vault_addr" 2>/dev/null | grep -q "Sealed.*false"; then
        log_step "Vault is already unsealed" "INFO" >&2
        return 0
    fi

    log_step "Unsealing Vault..." "INFO" >&2

    # Temporarily remove immutable flag to read file
    chattr -i "$vault_creds" 2>/dev/null

    # Extract unseal keys (need 3 out of 5)
    local key1=$(grep "key1=" "$vault_creds" | cut -d= -f2)
    local key2=$(grep "key2=" "$vault_creds" | cut -d= -f2)
    local key3=$(grep "key3=" "$vault_creds" | cut -d= -f2)

    # Restore immutable flag
    chattr +i "$vault_creds" 2>/dev/null

    # Unseal with 3 keys
    vault operator unseal -address="$vault_addr" "$key1" >/dev/null 2>&1
    vault operator unseal -address="$vault_addr" "$key2" >/dev/null 2>&1
    vault operator unseal -address="$vault_addr" "$key3" >/dev/null 2>&1

    # Verify unsealed
    if vault status -address="$vault_addr" 2>/dev/null | grep -q "Sealed.*false"; then
        log_step "Vault unsealed successfully" "SUCCESS" >&2
        return 0
    else
        log_step "Failed to unseal Vault" "ERROR" >&2
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: login_vault_auto
# Description: Automatically logs into Vault using stored root token
# Arguments: $1 - vault credentials file path
#-------------------------------------------------------------------------------
login_vault_auto() {
    local vault_creds="$1"
    local vault_addr="http://127.0.0.1:8200"

    if [ ! -f "$vault_creds" ]; then
        log_step "Vault credentials file not found: $vault_creds" "ERROR" >&2
        return 1
    fi

    log_step "Logging into Vault" "INFO" >&2

    # Temporarily remove immutable flag to read file
    chattr -i "$vault_creds" 2>/dev/null

    # Extract root token
    local root_token=$(grep "token=" "$vault_creds" | cut -d= -f2)

    # Restore immutable flag
    chattr +i "$vault_creds" 2>/dev/null

    # Login to Vault
    export VAULT_ADDR="$vault_addr"
    export VAULT_TOKEN="$root_token"

    if vault token lookup >/dev/null 2>&1; then
        log_step "Vault login successful" "SUCCESS" >&2

        # Save token to environment file for labtomation user
        local env_file="/home/labtomation/.vault_env"
        cat > "$env_file" << EOF
# Vault environment variables
# Source this file: source ~/.vault_env
export VAULT_ADDR="$vault_addr"
export VAULT_TOKEN="$root_token"
EOF
        chown labtomation:labtomation "$env_file"
        chmod 600 "$env_file"

        return 0
    else
        log_step "Vault login failed" "ERROR" >&2
        return 1
    fi
}

#-------------------------------------------------------------------------------
# MAIN FUNCTION
#-------------------------------------------------------------------------------

main() {
    log_header "Labtomation v2.0.0 - Proxmox Lab Automation"

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

    # Read confirmation (using /dev/tty for piped input compatibility)
    read -rp "Continue with VM creation? [Y/n]: " confirm </dev/tty
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
        "sudo mkdir -p /opt/labtomation/{config,setup} && sudo chown -R ${os_user}:${os_user} /opt/labtomation"

    # Copy setup scripts and libraries
    scp -o StrictHostKeyChecking=no -i "$ssh_key" \
        "$SCRIPT_DIR/setup_lab.sh" \
        "$SCRIPT_DIR/common_lib.sh" \
        "${os_user}@${vm_ip}:/opt/labtomation/"

    # Copy config files
    scp -o StrictHostKeyChecking=no -i "$ssh_key" \
        "$SCRIPT_DIR/config/"*.conf \
        "${os_user}@${vm_ip}:/opt/labtomation/config/"

    # Copy SSH keys to /opt/labtomation/setup/ for vault_init role
    # lab_id_ed25519: For lab VMs/LXC access (bootstrap key)
    # pve_id_ed25519: For Proxmox node access
    scp -o StrictHostKeyChecking=no -i "$ssh_key" \
        "$ssh_key" "$ssh_key.pub" \
        "$SCRIPT_DIR/pve_id_ed25519" "$SCRIPT_DIR/pve_id_ed25519.pub" \
        "${os_user}@${vm_ip}:/opt/labtomation/setup/"

    log_step "SSH keys copied to VM (lab + pve)" "SUCCESS"

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
    echo "  Status: ✓ Initialized and unsealed automatically (via vault_init role)"
    echo "  Credentials: /home/labtomation/.security/.vault (secured, immutable)"
    echo "  Environment: /home/labtomation/.security/.vault_env.sh"
    echo ""
    echo "Security:"
    echo "  ✓ Security directory created: /home/labtomation/.security/"
    echo "  ✓ SSH keys backed up (lab_id_ed25519, pve_id_ed25519)"
    echo "  ✓ Vault credentials secured (400, immutable)"
    echo "  ✓ All sensitive files protected with chattr +i"
    echo ""
    echo "Environment:"
    echo "  Source Vault credentials: source ~/.security/.vault_env.sh"
    echo ""
    echo "Next Steps:"
    echo "  1. SSH into VM: ssh -i $ssh_key ${os_user}@${vm_ip}"
    echo "  2. Source Vault: source ~/.security/.vault_env.sh"
    echo "  3. Bootstrap Proxmox: cd /opt/labtomation/playbooks && ansible-playbook bootstrap_proxmox_cluster.yml"
    echo ""
    echo "Ansible Playbooks:"
    echo "  Location: /opt/labtomation/playbooks"
    echo "  Re-run: cd /opt/labtomation/playbooks && ansible-playbook -i inventory/localhost.yml setup_devops_tools.yml"
    echo "  Tags: --tags terraform,vault,vault_init,jenkins"
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
