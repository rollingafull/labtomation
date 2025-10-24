#!/bin/bash

#===============================================================================
# Title: Proxmox VE Functions Library for Lab Setup
# Description: Functions for setting up Ansible management and DevOps tools
#-------------------------------------------------------------------------------
# Author: rolling (rolling@a-full.com)
# Created: 2025-10-04
# Updated: 2025-10-20
# Version: 2.0.0
#===============================================================================

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/common_lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/devops_tools_lib.sh"

#-------------------------------------------------------------------------------
# SSH KEY MANAGEMENT
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: setup_ssh_key
# Description: Checks for and generates SSH key pair if needed
# Arguments: None
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
setup_ssh_key() {
    local key_file="${SSH_KEY_PATH:-./setup/id_ed25519}"
    local pub_key="${key_file}.pub"
    local key_type="${SSH_KEY_TYPE:-ed25519}"
    local key_comment="${SSH_KEY_COMMENT:-labtomation@proxmox}"

    if [ -f "$pub_key" ]; then
        log_step "SSH key already exists" "SKIP" "$pub_key"
        return 0
    fi

    log_step "Generating new $key_type SSH key" "START"

    mkdir -p "$(dirname "$key_file")"
    chmod 700 "$(dirname "$key_file")"

    if ! ssh-keygen -t "$key_type" -f "$key_file" -N "" -C "$key_comment"; then
        log_step "Failed to generate SSH key" "FAILED"
        return 1
    fi

    chmod 600 "$key_file"
    chmod 644 "$pub_key"

    log_step "SSH key generated successfully" "SUCCESS" "$pub_key"
    return 0
}

#-------------------------------------------------------------------------------
# NETWORK AND NODE DETECTION
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: detect_proxmox_nodes
# Description: Scans network for Proxmox VE nodes
# Arguments:
#   $1 - network: Network CIDR to scan
# Returns: Space-separated list of node IPs
#-------------------------------------------------------------------------------
detect_proxmox_nodes() {
    local network=$1
    local nodes=()

    log_step "Scanning network $network for Proxmox nodes" "START"

    # Check if nmap is available
    if ! command -v nmap &>/dev/null; then
        log_step "Installing nmap" "INFO"
        install_system_packages nmap
    fi

    while read -r ip; do
        # Check if port 8006 (Proxmox web UI) is open
        if nc -z -w1 "$ip" 8006 2>/dev/null; then
            # Verify it's actually Proxmox
            if curl -sk "https://$ip:8006" 2>/dev/null | grep -q "Proxmox"; then
                nodes+=("$ip")
                log_step "Found Proxmox node" "SUCCESS" "$ip"
            fi
        fi
    done < <(nmap -n -sn "$network" -oG - 2>/dev/null | awk '/Up$/{print $2}')

    if [ ${#nodes[@]} -eq 0 ]; then
        log_step "No Proxmox nodes found in network" "WARN"
        return 1
    fi

    log_step "Found ${#nodes[@]} Proxmox node(s)" "SUCCESS"
    echo "${nodes[@]}"
    return 0
}

#-------------------------------------------------------------------------------
# PROXMOX NODE SETUP
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: setup_ansible_user
# Description: Creates ansible user and configures SSH access
# Arguments:
#   $1 - node: Proxmox node IP
#   $2 - password: Root password
#   $3 - pub_key: Path to SSH public key
#   $4 - disable_root: Disable root SSH (true/false)
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
setup_ansible_user() {
    local node=$1
    local password=$2
    local pub_key=$3
    local disable_root=${4:-false}
    local ansible_user="ansible"

    log_step "Setting up ansible user on $node" "START"

    # Check if user already exists
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no "root@$node" \
        "id $ansible_user" &>/dev/null; then
        log_step "User $ansible_user already exists" "SKIP"
    else
        # Create user
        if ! sshpass -p "$password" ssh -o StrictHostKeyChecking=no "root@$node" "
            useradd -m -s /bin/bash '$ansible_user' || true

            # Configure sudo
            echo '$ansible_user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ansible
            chmod 0440 /etc/sudoers.d/ansible

            # Create .ssh directory
            mkdir -p /home/$ansible_user/.ssh
            chmod 700 /home/$ansible_user/.ssh
            chown $ansible_user:$ansible_user /home/$ansible_user/.ssh
        "; then
            log_step "Failed to create ansible user" "FAILED"
            return 1
        fi

        log_step "Ansible user created" "SUCCESS"
    fi

    # Copy SSH key
    log_step "Configuring SSH key" "INFO"
    if ! sshpass -p "$password" ssh-copy-id -f -o StrictHostKeyChecking=no \
        -i "$pub_key" "$ansible_user@$node" &>/dev/null; then
        log_step "Failed to copy SSH key" "FAILED"
        return 1
    fi

    # Optionally disable root SSH
    if [ "$disable_root" = "true" ]; then
        log_step "Disabling root SSH access" "INFO"
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no "root@$node" "
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            systemctl restart sshd
        " || log_step "Failed to disable root SSH" "WARN"
    fi

    log_step "Ansible user configured successfully" "SUCCESS"
    return 0
}

#-------------------------------------------------------------------------------
# Function: create_api_token
# Description: Creates Proxmox API token for automation
# Arguments:
#   $1 - node: Proxmox node IP
#   $2 - password: Root password
#   $3 - token_id: Token identifier (default: ansible-token)
# Returns: API token on success, empty on failure
#-------------------------------------------------------------------------------
create_api_token() {
    local node=$1
    local password=$2
    local token_id=${3:-ansible-token}

    log_step "Creating API token on $node" "START"

    # Install jq if not present
    if ! command -v jq &>/dev/null; then
        install_system_packages jq
    fi

    # Login to get ticket
    local login_response
    login_response=$(curl -sk -d "username=root@pam&password=$password" \
        "https://$node:8006/api2/json/access/ticket" 2>/dev/null)

    local ticket
    ticket=$(echo "$login_response" | jq -r '.data.ticket // empty')
    local csrf_token
    csrf_token=$(echo "$login_response" | jq -r '.data.CSRFPreventionToken // empty')

    if [ -z "$ticket" ] || [ "$ticket" = "null" ]; then
        log_step "Failed to login to Proxmox API" "FAILED"
        return 1
    fi

    # Check if token already exists
    local existing_token
    existing_token=$(curl -sk \
        -H "Cookie: PVEAuthCookie=$ticket" \
        -H "CSRFPreventionToken: $csrf_token" \
        "https://$node:8006/api2/json/access/users/root@pam/token/$token_id" 2>/dev/null)

    if echo "$existing_token" | jq -e '.data' &>/dev/null; then
        log_step "API token already exists" "WARN" "Cannot retrieve existing token value"
        log_step "Please delete existing token or use different token_id" "INFO"
        return 1
    fi

    # Create new token
    local token_response
    token_response=$(curl -sk -X POST \
        -H "Cookie: PVEAuthCookie=$ticket" \
        -H "CSRFPreventionToken: $csrf_token" \
        -H "Content-Type: application/json" \
        -d "{\"userid\":\"root@pam\",\"comment\":\"Token for Ansible automation\",\"privsep\":1}" \
        "https://$node:8006/api2/json/access/users/root@pam/token/$token_id" 2>/dev/null)

    local api_token
    api_token=$(echo "$token_response" | jq -r '.data.value // empty')

    if [ -z "$api_token" ] || [ "$api_token" = "null" ]; then
        log_step "Failed to create API token" "FAILED"
        return 1
    fi

    log_step "API token created successfully" "SUCCESS"
    echo "$api_token"
    return 0
}

#-------------------------------------------------------------------------------
# HASHICORP VAULT SETUP
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: setup_hashicorp_vault
# Description: Sets up HashiCorp Vault with systemd service
# Arguments:
#   $1 - api_token: Proxmox API token to store
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
setup_hashicorp_vault() {
    local api_token=$1
    local base_dir="${VAULT_DIR:-./vault}"
    local vault_addr="${VAULT_ADDR:-http://127.0.0.1:8200}"
    local service_name="${VAULT_SERVICE_NAME:-vault-lab}"

    log_step "Setting up HashiCorp Vault" "START"

    # Create directory structure
    mkdir -p "$base_dir"/{config,data,policies,logs}

    # Check if Vault is already running
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log_step "Vault service already running" "INFO"
        export VAULT_ADDR="$vault_addr"

        # Check if initialized
        if vault status 2>&1 | grep -q "Initialized.*true"; then
            # Load existing token
            if [ -f "$base_dir/.vault_token" ]; then
                export VAULT_TOKEN=$(cat "$base_dir/.vault_token")
                log_step "Vault already configured" "SKIP"
                return 0
            else
                log_step "Vault initialized but token not found" "WARN"
                log_step "Please provide root token or reinitialize Vault" "INFO"
                return 1
            fi
        fi
    fi

    # Install Vault if not present
    if ! command -v vault &>/dev/null; then
        install_vault
    fi

    # Generate Vault configuration
    cat > "$base_dir/config/vault.hcl" << EOF
storage "file" {
    path = "$(realpath "$base_dir/data")"
}

listener "tcp" {
    address = "127.0.0.1:8200"
    tls_disable = 1
}

ui = true
disable_mlock = true
log_level = "Info"
EOF

    # Create systemd service
    log_step "Creating systemd service for Vault" "INFO"

    sudo tee "/etc/systemd/system/${service_name}.service" > /dev/null << EOF
[Unit]
Description=HashiCorp Vault for Lab Management
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$(realpath "$base_dir/config/vault.hcl")

[Service]
Type=notify
User=$(whoami)
Group=$(id -gn)
ExecStart=/usr/bin/vault server -config=$(realpath "$base_dir/config/vault.hcl")
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and start Vault
    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    sudo systemctl start "$service_name"

    # Wait for Vault to be ready
    export VAULT_ADDR="$vault_addr"
    local max_wait=30
    local waited=0

    log_step "Waiting for Vault to start" "INFO"
    while ! vault status &>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [ $waited -ge $max_wait ]; then
            log_step "Timeout waiting for Vault" "FAILED"
            return 1
        fi
    done

    # Initialize Vault
    if vault status 2>&1 | grep -q "Initialized.*false"; then
        log_step "Initializing Vault" "INFO"

        vault operator init \
            -key-shares="${VAULT_KEY_SHARES:-5}" \
            -key-threshold="${VAULT_KEY_THRESHOLD:-3}" \
            -format=json > "$base_dir/init.json"

        chmod 600 "$base_dir/init.json"

        # Extract and save root token
        jq -r '.root_token' "$base_dir/init.json" > "$base_dir/.vault_token"
        chmod 600 "$base_dir/.vault_token"
        export VAULT_TOKEN=$(cat "$base_dir/.vault_token")

        # Auto-unseal if enabled
        if [ "${VAULT_AUTO_UNSEAL:-true}" = "true" ]; then
            log_step "Auto-unsealing Vault" "INFO"

            local threshold=${VAULT_KEY_THRESHOLD:-3}
            for ((i=0; i<threshold; i++)); do
                local key
                key=$(jq -r ".unseal_keys_b64[$i]" "$base_dir/init.json")
                vault operator unseal "$key" &>/dev/null
            done

            log_step "Vault unsealed successfully" "SUCCESS"
        fi

        echo ""
        echo "================================================"
        echo "⚠️  IMPORTANT: Vault Initialization Complete"
        echo "================================================"
        echo "Root token saved to: $base_dir/.vault_token"
        echo "Unseal keys saved to: $base_dir/init.json"
        echo ""
        echo "BACKUP THESE FILES IMMEDIATELY!"
        echo "Store them in a secure location separate from this server."
        echo "================================================"
        echo ""
    else
        # Already initialized, load token
        if [ -f "$base_dir/.vault_token" ]; then
            export VAULT_TOKEN=$(cat "$base_dir/.vault_token")
        fi
    fi

    # Enable KV secrets engine
    vault secrets list | grep -q '^secret/' || \
        vault secrets enable -path=secret kv-v2

    # Store Proxmox API credentials
    log_step "Storing Proxmox credentials in Vault" "INFO"
    vault kv put secret/proxmox/api \
        token_id="root@pam!ansible-token" \
        token_secret="$api_token"

    # Create Ansible policy
    cat > "$base_dir/policies/ansible.hcl" << 'EOF'
path "secret/data/proxmox/*" {
    capabilities = ["read", "list"]
}

path "secret/metadata/proxmox/*" {
    capabilities = ["read", "list"]
}
EOF

    vault policy write ansible "$base_dir/policies/ansible.hcl"

    # Create token for Ansible
    local ansible_token
    ansible_token=$(vault token create -policy=ansible -format=json | jq -r '.auth.client_token')
    echo "$ansible_token" > "$base_dir/.ansible_vault_token"
    chmod 600 "$base_dir/.ansible_vault_token"

    log_step "Vault configured successfully" "SUCCESS"
    log_step "Ansible token: $base_dir/.ansible_vault_token" "INFO"

    return 0
}

#-------------------------------------------------------------------------------
# ANSIBLE SETUP
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: setup_ansible_structure
# Description: Creates Ansible directory structure with Vault integration
# Arguments: None
# Returns: 0 on success
#-------------------------------------------------------------------------------
setup_ansible_structure() {
    local base_dir="${ANSIBLE_DIR:-./ansible}"
    local vault_addr="${VAULT_ADDR:-http://127.0.0.1:8200}"

    log_step "Setting up Ansible directory structure" "START"

    # Create directories
    mkdir -p "$base_dir"/{inventory,group_vars,host_vars,roles,playbooks,collections}

    # Create ansible.cfg
    cat > "$base_dir/ansible.cfg" << EOF
[defaults]
inventory = ./inventory/proxmox.yml
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600
roles_path = ./roles:~/.ansible/roles:/usr/share/ansible/roles
collections_paths = ./collections:~/.ansible/collections:/usr/share/ansible/collections
vault_addr = $vault_addr

[inventory]
enable_plugins = host_list, script, auto, yaml, ini, toml

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
EOF

    # Create inventory file
    cat > "$base_dir/inventory/proxmox.yml" << 'EOF'
---
all:
  children:
    proxmox_hosts:
      hosts:
      vars:
        ansible_user: ansible
        ansible_ssh_private_key_file: "../setup/id_ed25519"
EOF

    # Create group_vars
    cat > "$base_dir/group_vars/proxmox_hosts/vars.yml" << 'EOF'
---
# Proxmox configuration
proxmox_api_host: "{{ inventory_hostname }}"
proxmox_api_port: 8006
proxmox_api_token_id: "{{ lookup('env', 'PROXMOX_TOKEN_ID') | default('root@pam!ansible-token') }}"
# Token secret should be retrieved from Vault in playbooks
EOF

    # Create example playbook
    cat > "$base_dir/playbooks/ping.yml" << 'EOF'
---
- name: Test Ansible connectivity
  hosts: proxmox_hosts
  gather_facts: yes
  tasks:
    - name: Ping test
      ansible.builtin.ping:

    - name: Display hostname
      ansible.builtin.debug:
        msg: "Connected to {{ ansible_hostname }} ({{ ansible_distribution }} {{ ansible_distribution_version }})"
EOF

    # Create README
    cat > "$base_dir/README.md" << 'EOF'
# Ansible Configuration for Proxmox Lab

## Usage

Test connectivity:
```bash
cd ansible
ansible proxmox_hosts -m ping
ansible-playbook playbooks/ping.yml
```

## Vault Integration

Proxmox API credentials are stored in HashiCorp Vault.

To retrieve them in playbooks:
```yaml
- name: Get Proxmox API token from Vault
  set_fact:
    proxmox_token_secret: "{{ lookup('hashivault', 'secret/proxmox/api', 'token_secret') }}"
```

## Directory Structure

- `inventory/` - Inventory files
- `group_vars/` - Group variables
- `host_vars/` - Host-specific variables
- `roles/` - Ansible roles
- `playbooks/` - Playbooks
- `collections/` - Ansible collections
EOF

    log_step "Ansible structure created" "SUCCESS"
    return 0
}

#-------------------------------------------------------------------------------
# POST-INSTALLATION TESTS
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: run_post_installation_tests
# Description: Tests installed tools and connectivity
# Arguments:
#   $1 - vm_ip: IP address to test (optional, tests local if not provided)
#   $2 - ssh_user: SSH user (default: ansible)
#   $3 - ssh_key: SSH key path
# Returns: Number of failed tests
#-------------------------------------------------------------------------------
run_post_installation_tests() {
    local vm_ip=${1:-}
    local ssh_user=${2:-ansible}
    local ssh_key=${3:-./setup/id_ed25519}
    local failed=0
    local ssh_prefix=""

    log_step "Running post-installation tests" "START"
    echo ""

    # If VM IP provided, test remote system
    if [ -n "$vm_ip" ]; then
        ssh_prefix="ssh -o BatchMode=yes -o ConnectTimeout=5 -i $ssh_key ${ssh_user}@${vm_ip}"

        # Test SSH connectivity first
        if $ssh_prefix "echo 'SSH OK'" &>/dev/null; then
            log_step "SSH connectivity" "SUCCESS"
        else
            log_step "SSH connectivity" "FAILED"
            return 1
        fi
    fi

    # Test Ansible
    if $ssh_prefix command -v ansible &>/dev/null; then
        local version
        version=$($ssh_prefix ansible --version 2>/dev/null | head -1 | awk '{print $3}')
        log_step "Ansible" "SUCCESS" "version $version"
    else
        log_step "Ansible" "FAILED"
        ((failed++))
    fi

    # Test Terraform
    if $ssh_prefix command -v terraform &>/dev/null; then
        local version
        version=$($ssh_prefix terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
        log_step "Terraform" "SUCCESS" "version $version"
    else
        log_step "Terraform" "FAILED"
        ((failed++))
    fi

    # Test Vault
    if $ssh_prefix command -v vault &>/dev/null; then
        local version
        version=$($ssh_prefix vault version 2>/dev/null | awk '{print $2}')
        log_step "Vault" "SUCCESS" "$version"
    else
        log_step "Vault" "FAILED"
        ((failed++))
    fi

    # Test Jenkins
    if $ssh_prefix systemctl is-active jenkins &>/dev/null; then
        log_step "Jenkins service" "SUCCESS" "running"
    else
        log_step "Jenkins service" "SKIP" "not installed or not running"
    fi

    # Test Docker
    if $ssh_prefix command -v docker &>/dev/null; then
        local version
        version=$($ssh_prefix docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        log_step "Docker" "SUCCESS" "version $version"
    else
        log_step "Docker" "SKIP" "not installed"
    fi

    echo ""
    if [ $failed -eq 0 ]; then
        log_step "All tests passed" "SUCCESS"
    else
        log_step "$failed test(s) failed" "WARN"
    fi

    return $failed
}

# Export functions
export -f setup_ssh_key
export -f detect_proxmox_nodes
export -f setup_ansible_user
export -f create_api_token
export -f setup_hashicorp_vault
export -f setup_ansible_structure
export -f run_post_installation_tests
