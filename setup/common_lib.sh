#!/bin/bash

#===============================================================================
# Title: Common Functions Library for Labtomation
# Description: Shared functions for logging, state management, downloads, etc.
#-------------------------------------------------------------------------------
# Author: rolling (rolling@a-full.com)
# Created: 2025-10-20
# Updated: 2025-10-20
# Version: 2.0.0
#===============================================================================

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configurations
load_configs() {
    local config_dir="${SCRIPT_DIR}/config"

    # Debug: Show what we're trying to load
    # echo "DEBUG: Loading configs from: $config_dir" >&2

    # Load all config files
    if [ -f "$config_dir/labtomation.conf" ]; then
        # shellcheck source=/dev/null
        source "$config_dir/labtomation.conf"
    else
        echo "WARNING: Config file not found: $config_dir/labtomation.conf" >&2
    fi

    if [ -f "$config_dir/os_configs.conf" ]; then
        # shellcheck source=/dev/null
        source "$config_dir/os_configs.conf"
    else
        echo "WARNING: Config file not found: $config_dir/os_configs.conf" >&2
    fi

    if [ -f "$config_dir/hardware_configs.conf" ]; then
        # shellcheck source=/dev/null
        source "$config_dir/hardware_configs.conf"
    else
        echo "WARNING: Config file not found: $config_dir/hardware_configs.conf" >&2
    fi

    if [ -f "$config_dir/network_configs.conf" ]; then
        # shellcheck source=/dev/null
        source "$config_dir/network_configs.conf"
    else
        echo "WARNING: Config file not found: $config_dir/network_configs.conf" >&2
    fi

    # Set default paths relative to script directory
    STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/state}"
    LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
    CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR/config}"

    # Ensure directories exist
    mkdir -p "$STATE_DIR" "$LOG_DIR"
}

# Initialize on source
load_configs

#-------------------------------------------------------------------------------
# LOGGING FUNCTIONS
#-------------------------------------------------------------------------------

# Log file for current script
LOG_FILE=""

#-------------------------------------------------------------------------------
# Function: setup_logging
# Description: Initializes logging for the script
# Arguments:
#   $1 - script_name: Name of the script (without .sh)
# Returns: 0 on success
#-------------------------------------------------------------------------------
setup_logging() {
    local script_name=${1:-"labtomation"}
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    LOG_FILE="${LOG_DIR}/${script_name}_${timestamp}.log"

    # Create log file
    touch "$LOG_FILE"

    # Redirect stdout and stderr to both console and log file
    exec > >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)

    log_header "$script_name"

    # Cleanup old logs
    cleanup_old_logs
}

#-------------------------------------------------------------------------------
# Function: log_header
# Description: Prints log file header
# Arguments:
#   $1 - script_name: Name of the script
#-------------------------------------------------------------------------------
log_header() {
    local script_name=$1

    echo "==================================================="
    echo "Labtomation Log - $script_name"
    echo "==================================================="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Script: ${BASH_SOURCE[1]:-$0}"
    echo "User: $(whoami)"
    echo "Host: $(hostname)"
    echo "Working Directory: $(pwd)"
    echo "==================================================="
    echo ""
}

#-------------------------------------------------------------------------------
# Function: log_step
# Description: Logs a step with status
# Arguments:
#   $1 - step: Step description
#   $2 - status: START, SUCCESS, FAILED, SKIP, INFO
#   $3 - message: Additional message (optional)
#-------------------------------------------------------------------------------
log_step() {
    local step=$1
    local status=$2
    local message=${3:-}
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$status" in
        START)
            echo "[$timestamp] ▶️  STARTING: $step"
            ;;
        SUCCESS)
            echo "[$timestamp] ✅ SUCCESS: $step${message:+ - $message}"
            ;;
        FAILED)
            echo "[$timestamp] ❌ FAILED: $step${message:+ - $message}"
            ;;
        SKIP)
            echo "[$timestamp] ⏭️  SKIPPED: $step${message:+ - $message}"
            ;;
        INFO)
            echo "[$timestamp] ℹ️  INFO: $step${message:+ - $message}"
            ;;
        WARN)
            echo "[$timestamp] ⚠️  WARNING: $step${message:+ - $message}"
            ;;
        *)
            echo "[$timestamp] $step${message:+ - $message}"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# Function: cleanup_old_logs
# Description: Removes log files older than configured retention period
#-------------------------------------------------------------------------------
cleanup_old_logs() {
    local retention_days=${LOG_RETENTION_DAYS:-30}

    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -name "*.log" -type f -mtime +"${retention_days}" -delete 2>/dev/null || true
    fi
}

#-------------------------------------------------------------------------------
# STATE MANAGEMENT FUNCTIONS
#-------------------------------------------------------------------------------

STATE_FILE="${STATE_DIR}/labtomation.state"

#-------------------------------------------------------------------------------
# Function: save_state
# Description: Saves a key-value pair to state file
# Arguments:
#   $1 - key: State variable name
#   $2 - value: State variable value
#-------------------------------------------------------------------------------
save_state() {
    local key=$1
    local value=$2

    mkdir -p "$(dirname "$STATE_FILE")"

    # Remove existing key and add new value
    if [ -f "$STATE_FILE" ]; then
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi

    echo "${key}=${value}" >> "$STATE_FILE"
}

#-------------------------------------------------------------------------------
# Function: load_state
# Description: Loads a value from state file
# Arguments:
#   $1 - key: State variable name
#   $2 - default: Default value if key not found (optional)
# Returns: Value from state or default
#-------------------------------------------------------------------------------
load_state() {
    local key=$1
    local default=${2:-}

    if [ -f "$STATE_FILE" ]; then
        local value
        value=$(grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2-)
        echo "${value:-$default}"
    else
        echo "$default"
    fi
}

#-------------------------------------------------------------------------------
# Function: clear_state
# Description: Removes all state for a fresh start
#-------------------------------------------------------------------------------
clear_state() {
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        log_step "State cleared" "INFO"
    fi
}

#-------------------------------------------------------------------------------
# Function: acquire_lock
# Description: Acquires a lock file to prevent concurrent execution
# Arguments:
#   $1 - lock_name: Name of the lock
# Returns: 0 if lock acquired, 1 if already locked
#-------------------------------------------------------------------------------
acquire_lock() {
    local lock_name=$1
    local lock_file="${STATE_DIR}/${lock_name}.lock"

    if [ -f "$lock_file" ]; then
        local pid
        pid=$(cat "$lock_file" 2>/dev/null)

        # Check if process is still running
        if kill -0 "$pid" 2>/dev/null; then
            log_step "Lock already held by process $pid" "FAILED"
            return 1
        else
            # Stale lock, remove it
            rm -f "$lock_file"
        fi
    fi

    # Create lock file with current PID
    echo $$ > "$lock_file"

    # Set trap to remove lock on exit
    # shellcheck disable=SC2064
    trap "rm -f '$lock_file'" EXIT

    return 0
}

#-------------------------------------------------------------------------------
# DOWNLOAD FUNCTIONS
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: download_file_idempotent
# Description: Downloads a file with retry logic and integrity checking
# Arguments:
#   $1 - url: URL to download from
#   $2 - output: Output file path
#   $3 - checksum_url: Optional checksum URL for verification
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
download_file_idempotent() {
    local url=$1
    local output=$2
    local checksum_url=${3:-}
    local max_retries=${DOWNLOAD_MAX_RETRIES:-3}
    local timeout=${DOWNLOAD_TIMEOUT:-30}

    # Check if file already exists and is valid
    if [ -f "$output" ]; then
        log_step "File already exists: $output" "INFO"

        # Verify integrity based on file type
        if [[ "$output" =~ \.qcow2$ ]] || [[ "$output" =~ \.img$ ]]; then
            if qemu-img info "$output" >/dev/null 2>&1; then
                log_step "Image is valid, skipping download" "SKIP"
                return 0
            else
                log_step "Image corrupted, re-downloading" "WARN"
                rm -f "$output"
            fi
        elif [[ "$output" =~ \.tar\. ]]; then
            if tar -tzf "$output" >/dev/null 2>&1; then
                log_step "Archive is valid, skipping download" "SKIP"
                return 0
            else
                log_step "Archive corrupted, re-downloading" "WARN"
                rm -f "$output"
            fi
        else
            # For other files, just check if not empty
            if [ -s "$output" ]; then
                log_step "File exists and not empty, skipping download" "SKIP"
                return 0
            fi
        fi
    fi

    # Download with retries
    local retry=0
    local wget_opts=(
        --progress=bar:force:noscroll
        --timeout="$timeout"
        --tries=1
    )

    if [ "${DOWNLOAD_CONTINUE:-true}" = "true" ]; then
        wget_opts+=(--continue)
    fi

    log_step "Downloading $url" "START"

    while [ "$retry" -lt "$max_retries" ]; do
        if wget "${wget_opts[@]}" "$url" -O "$output"; then
            # Download successful, verify checksum if provided
            if [ -n "$checksum_url" ] && [ "${ENABLE_CHECKSUMS:-true}" = "true" ]; then
                log_step "Verifying checksum" "INFO"

                local checksum_file="${output}.checksum"
                if wget -q "$checksum_url" -O "$checksum_file"; then
                    # Extract the relevant checksum line
                    local expected_sum
                    expected_sum=$(grep "$(basename "$output")" "$checksum_file" | awk '{print $1}')

                    if [ -n "$expected_sum" ]; then
                        local actual_sum
                        actual_sum=$(sha256sum "$output" | awk '{print $1}')

                        if [ "$expected_sum" = "$actual_sum" ]; then
                            log_step "Checksum verification passed" "SUCCESS"
                            rm -f "$checksum_file"
                            return 0
                        else
                            log_step "Checksum mismatch" "FAILED"
                            rm -f "$output" "$checksum_file"
                            retry=$((retry + 1))
                            continue
                        fi
                    fi
                    rm -f "$checksum_file"
                fi
            fi

            log_step "Download completed" "SUCCESS"
            return 0
        fi

        retry=$((retry + 1))
        if [ "$retry" -lt "$max_retries" ]; then
            log_step "Download failed, retry $retry/$max_retries" "WARN"
            sleep 5
        fi
    done

    log_step "Download failed after $max_retries attempts" "FAILED"
    return 1
}

#-------------------------------------------------------------------------------
# VALIDATION FUNCTIONS
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: validate_vmid
# Description: Validates VM/CT ID and checks availability
# Arguments:
#   $1 - vmid: VM/CT ID to validate
# Returns: 0 if valid and available, 1 otherwise
#-------------------------------------------------------------------------------
validate_vmid() {
    local vmid=$1

    # Check format
    if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
        log_step "VMID must be numeric" "FAILED"
        return 1
    fi

    # Check range
    if [ "$vmid" -lt 100 ] || [ "$vmid" -gt 999999 ]; then
        log_step "VMID must be between 100 and 999999" "FAILED"
        return 1
    fi

    # Check if in use
    if qm status "$vmid" >/dev/null 2>&1 || pct status "$vmid" >/dev/null 2>&1; then
        if [ "${SKIP_EXISTING_TEMPLATES:-true}" != "true" ]; then
            log_step "VMID $vmid is already in use" "FAILED"
            return 1
        fi
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Function: validate_network
# Description: Validates network CIDR notation
# Arguments:
#   $1 - network: Network in CIDR format (e.g., 192.168.1.0/24)
# Returns: 0 if valid, 1 otherwise
#-------------------------------------------------------------------------------
validate_network() {
    local network=$1

    if [ -z "$network" ]; then
        log_step "Network cannot be empty" "FAILED"
        return 1
    fi

    # Check format
    if ! echo "$network" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
        log_step "Invalid network format. Expected: xxx.xxx.xxx.xxx/xx" "FAILED"
        return 1
    fi

    # Validate octets
    local ip_addr subnet
    IFS='/' read -r ip_addr subnet <<< "$network"
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip_addr"

    for octet in $o1 $o2 $o3 $o4; do
        if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
            log_step "IP octets must be between 0 and 255" "FAILED"
            return 1
        fi
    done

    # Validate subnet mask
    if [ "$subnet" -gt 32 ] || [ "$subnet" -lt 0 ]; then
        log_step "Subnet mask must be between 0 and 32" "FAILED"
        return 1
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Function: validate_requirements
# Description: Checks if required commands are available
# Arguments:
#   $@ - List of required commands
# Returns: 0 if all present, 1 if any missing
#-------------------------------------------------------------------------------
validate_requirements() {
    local missing_commands=()

    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_step "Missing required commands: ${missing_commands[*]}" "FAILED"
        return 1
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Function: is_proxmox_node
# Description: Checks if running on a Proxmox VE node
# Returns: 0 if on Proxmox, 1 otherwise
#-------------------------------------------------------------------------------
is_proxmox_node() {
    if [ -f "/etc/pve/local/pve-ssl.key" ]; then
        return 0
    else
        log_step "Not running on a Proxmox VE node" "FAILED"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# ERROR HANDLING
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: error_handler
# Description: Global error handler for scripts
# Arguments:
#   $1 - line_no: Line number where error occurred
#   $2 - error_code: Exit code from failed command
#-------------------------------------------------------------------------------
error_handler() {
    local line_no=$1
    local error_code=$2
    local error_cmd

    echo ""
    echo "========== Error Details =========="
    echo "Script: ${BASH_SOURCE[1]:-$0}"
    echo "Line number: $line_no"
    echo "Exit code: $error_code"

    # Get failed command
    error_cmd=$(sed -n "${line_no}p" "${BASH_SOURCE[1]:-$0}" 2>/dev/null)
    if [ -n "$error_cmd" ]; then
        echo "Failed command: $error_cmd"
    fi

    echo "Working directory: $(pwd)"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=================================="
    echo ""

    # Don't cleanup state on error - allow resumption
    if [ "${ENABLE_STATE_PERSISTENCE:-true}" = "true" ]; then
        log_step "State preserved for resumption" "INFO"
    fi

    exit "$error_code"
}

#-------------------------------------------------------------------------------
# UTILITY FUNCTIONS
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: wait_for_ssh
# Description: Waits for SSH to become available
# Arguments:
#   $1 - ip: IP address to check
#   $2 - port: SSH port (default: 22)
#   $3 - timeout: Timeout in seconds (default: 300)
# Returns: 0 if SSH available, 1 on timeout
#-------------------------------------------------------------------------------
wait_for_ssh() {
    local ip=$1
    local port=${2:-22}
    local timeout=${3:-${VM_IP_WAIT_TIMEOUT:-300}}
    local elapsed=0

    log_step "Waiting for SSH on $ip:$port" "START"

    while ! nc -z -w1 "$ip" "$port" >/dev/null 2>&1; do
        if [ "$elapsed" -ge "$timeout" ]; then
            log_step "Timeout waiting for SSH" "FAILED"
            return 1
        fi

        sleep 5
        elapsed=$((elapsed + 5))

        # Show progress every 30 seconds
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_step "Still waiting... (${elapsed}s/${timeout}s)" "INFO"
        fi
    done

    # Additional wait for SSH to fully initialize
    sleep "${VM_BOOT_WAIT_TIME:-10}"

    log_step "SSH is available" "SUCCESS"
    return 0
}

#-------------------------------------------------------------------------------
# Function: get_os_config
# Description: Gets configuration value for an OS
# Arguments:
#   $1 - os_key: OS identifier (e.g., rocky10)
#   $2 - config_key: Configuration key (e.g., vm_url)
# Returns: Configuration value or empty string
#-------------------------------------------------------------------------------
get_os_config() {
    local os_key=$1
    local config_key=$2
    local var_name="${os_key}_${config_key}"

    echo "${!var_name:-}"
}

#-------------------------------------------------------------------------------
# Function: parse_date_url
# Description: Replaces {DATE} placeholder in URL with current/previous date
# Arguments:
#   $1 - url: URL with {DATE} placeholder
# Returns: URL with date replaced
#-------------------------------------------------------------------------------
parse_date_url() {
    local url=$1
    local current_date
    current_date=$(date +%Y%m%d)

    # Try current date first
    local parsed_url="${url//\{DATE\}/$current_date}"

    # Check if URL is accessible
    if wget --spider "$parsed_url" 2>/dev/null; then
        echo "$parsed_url"
        return 0
    fi

    # Try yesterday's date
    local yesterday_date
    yesterday_date=$(date -d "yesterday" +%Y%m%d)
    parsed_url="${url//\{DATE\}/$yesterday_date}"

    echo "$parsed_url"
}

#-------------------------------------------------------------------------------
# PROXMOX STORAGE DETECTION
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Function: detect_proxmox_storage
# Description: Detects available storage in Proxmox VE
# Arguments:
#   $1 - content_type: Type of content (images, rootdir, vztmpl, iso)
# Returns: List of available storage IDs
#-------------------------------------------------------------------------------
detect_proxmox_storage() {
    local content_type=${1:-images}
    local storages=()

    # Get all storages that support the requested content type
    while IFS= read -r line; do
        local storage_id
        storage_id=$(echo "$line" | awk '{print $1}')

        if [ -n "$storage_id" ] && [ "$storage_id" != "Name" ]; then
            storages+=("$storage_id")
        fi
    done < <(pvesm status --content "$content_type" 2>/dev/null | grep -E '^[a-zA-Z0-9-]+')

    if [ ${#storages[@]} -eq 0 ]; then
        log_step "No storage found for content type: $content_type" "WARN"
        return 1
    fi

    echo "${storages[@]}"
    return 0
}

#-------------------------------------------------------------------------------
# Function: get_best_storage
# Description: Selects the best storage for VMs/containers
# Arguments:
#   $1 - content_type: Type of content (images, rootdir)
#   $2 - prefer_type: Preferred storage type (zfs, lvm-thin, dir, lvm)
# Returns: Storage ID
#-------------------------------------------------------------------------------
get_best_storage() {
    local content_type=${1:-images}
    local prefer_type=${2:-}
    local available_storages

    # Get all available storages
    available_storages=$(detect_proxmox_storage "$content_type")

    if [ -z "$available_storages" ]; then
        log_step "No storage available for $content_type" "FAILED"
        return 1
    fi

    # Priority order: local-zfs > local-lvm > local (if no preference)
    local priority_order=("local-zfs" "local-lvm" "local")

    # If preference specified, check it first
    if [ -n "$prefer_type" ]; then
        for storage in $available_storages; do
            local storage_type
            storage_type=$(pvesm status --storage "$storage" 2>/dev/null | awk 'NR==2 {print $2}')

            if [ "$storage_type" = "$prefer_type" ]; then
                echo "$storage"
                return 0
            fi
        done
    fi

    # Try priority order
    for priority_storage in "${priority_order[@]}"; do
        for storage in $available_storages; do
            if [ "$storage" = "$priority_storage" ]; then
                echo "$storage"
                return 0
            fi
        done
    done

    # If nothing matched, return first available
    echo "$available_storages" | awk '{print $1}'
    return 0
}

#-------------------------------------------------------------------------------
# Function: detect_storage_type
# Description: Detects the type of a storage
# Arguments:
#   $1 - storage_id: Storage ID to check
# Returns: Storage type (zfs, lvm-thin, lvm, dir, etc.)
#-------------------------------------------------------------------------------
detect_storage_type() {
    local storage_id=$1

    if [ -z "$storage_id" ]; then
        return 1
    fi

    local storage_type
    storage_type=$(pvesm status --storage "$storage_id" 2>/dev/null | awk 'NR==2 {print $2}')

    if [ -n "$storage_type" ]; then
        echo "$storage_type"
        return 0
    fi

    return 1
}

#-------------------------------------------------------------------------------
# Function: validate_storage
# Description: Validates that a storage exists and supports content type
# Arguments:
#   $1 - storage_id: Storage ID to validate
#   $2 - content_type: Required content type (images, rootdir, etc.)
# Returns: 0 if valid, 1 if not
#-------------------------------------------------------------------------------
validate_storage() {
    local storage_id=$1
    local content_type=${2:-images}

    # Check if storage exists
    if ! pvesm status --storage "$storage_id" &>/dev/null; then
        log_step "Storage '$storage_id' does not exist" "FAILED" >&2
        return 1
    fi

    # Check if it supports the content type
    if ! pvesm status --storage "$storage_id" --content "$content_type" &>/dev/null; then
        log_step "Storage '$storage_id' does not support content type: $content_type" "FAILED" >&2
        return 1
    fi

    # Check available space
    local avail
    avail=$(pvesm status --storage "$storage_id" 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -n "$avail" ]; then
        # Convert to GB for display
        local avail_gb=$((avail / 1024 / 1024 / 1024))

        if [ "$avail_gb" -lt 5 ]; then
            log_step "Storage '$storage_id' has low space: ${avail_gb}GB" "WARN" >&2
        fi
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Function: get_storage_for_vm
# Description: Gets appropriate storage for VM (images content type)
# Returns: Storage ID
#-------------------------------------------------------------------------------
get_storage_for_vm() {
    local storage

    # Try to get from config first
    if [ -n "${DEFAULT_STORAGE:-}" ]; then
        if validate_storage "$DEFAULT_STORAGE" "images"; then
            echo "$DEFAULT_STORAGE"
            return 0
        else
            log_step "Configured storage '$DEFAULT_STORAGE' not valid, auto-detecting" "WARN" >&2
        fi
    fi

    # Auto-detect
    storage=$(get_best_storage "images" "zfs")

    if [ -n "$storage" ]; then
        local storage_type
        storage_type=$(detect_storage_type "$storage")
        log_step "Auto-detected VM storage: $storage (type: $storage_type)" "INFO" >&2
        echo "$storage"
        return 0
    fi

    log_step "No suitable storage found for VMs" "FAILED" >&2
    return 1
}

#-------------------------------------------------------------------------------
# Function: get_storage_for_lxc
# Description: Gets appropriate storage for LXC (rootdir content type)
# Returns: Storage ID
#-------------------------------------------------------------------------------
get_storage_for_lxc() {
    local storage

    # Try to get from config first
    if [ -n "${DEFAULT_STORAGE:-}" ]; then
        if validate_storage "$DEFAULT_STORAGE" "rootdir"; then
            echo "$DEFAULT_STORAGE"
            return 0
        else
            log_step "Configured storage '$DEFAULT_STORAGE' not valid, auto-detecting" "WARN" >&2
        fi
    fi

    # Auto-detect
    storage=$(get_best_storage "rootdir" "zfs")

    if [ -n "$storage" ]; then
        local storage_type
        storage_type=$(detect_storage_type "$storage")
        log_step "Auto-detected LXC storage: $storage (type: $storage_type)" "INFO" >&2
        echo "$storage"
        return 0
    fi

    log_step "No suitable storage found for LXC" "FAILED" >&2
    return 1
}

# Export functions for use in subshells
export -f log_step
export -f log_header
export -f save_state
export -f load_state
export -f validate_vmid
export -f validate_network
export -f get_os_config
export -f parse_date_url
export -f detect_proxmox_storage
export -f get_best_storage
export -f detect_storage_type
export -f validate_storage
export -f get_storage_for_vm
export -f get_storage_for_lxc
