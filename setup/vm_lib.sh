#!/bin/bash

#===============================================================================
# Title: VM Management Library
# Description: Functions for creating and configuring Proxmox VMs
#-------------------------------------------------------------------------------
# Author: rolling (rolling@a-full.com)
# Created: 2025-10-20
# Version: 2.1.0
#===============================================================================

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/common_lib.sh"

#-------------------------------------------------------------------------------
# Function: check_numa_support
# Description: Checks if the host supports NUMA and installs numactl if needed
# Arguments: None
# Returns: 0 if NUMA is supported, 1 if not
# Globals: Sets NUMA_SUPPORTED=1 if supported
#-------------------------------------------------------------------------------
check_numa_support() {
    local numa_nodes=0

    # Check if numactl is installed (Proxmox is Debian-based)
    if ! command -v numactl &>/dev/null; then
        log_step "numactl not found, installing..." "INFO" >&2

        # Install numactl using apt
        apt-get update -qq &>/dev/null
        apt-get install -y numactl &>/dev/null

        # Verify installation
        if ! command -v numactl &>/dev/null; then
            log_step "Failed to install numactl" "WARN" >&2
            export NUMA_SUPPORTED=0
            return 1
        fi

        log_step "numactl installed successfully" "SUCCESS" >&2
    fi

    # Check NUMA support - need at least 2 nodes for NUMA to be beneficial
    numa_nodes=$(numactl --hardware 2>/dev/null | grep -c "^node [0-9]" || echo "0")

    if [ "$numa_nodes" -gt 1 ]; then
        log_step "NUMA detected: $numa_nodes nodes available" "SUCCESS" >&2
        export NUMA_SUPPORTED=1
        export NUMA_NODES="$numa_nodes"
        return 0
    else
        log_step "NUMA not beneficial: single node system detected" "INFO" >&2
        export NUMA_SUPPORTED=0
        export NUMA_NODES=1
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: generate_vmid
# Description: Generates next available VMID considering cluster/standalone mode
# Arguments: None
# Returns: Available VMID (stdout)
# Globals: None
#-------------------------------------------------------------------------------
generate_vmid() {
    local max_vm_id max_lxc_id max_id all_vmids

    # Check if node is part of a cluster
    if pvecm status &>/dev/null; then
        log_step "Detected Proxmox cluster" "INFO" >&2

        # Get all VMIDs from cluster using Proxmox API
        all_vmids=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
                    jq -r '.[].vmid' 2>/dev/null | sort -n)

        if [ -n "$all_vmids" ]; then
            max_id=$(echo "$all_vmids" | tail -1)
        else
            max_id=99
        fi
    else
        log_step "Standalone Proxmox node" "INFO" >&2

        # Standalone node - check local VMs and LXCs
        max_vm_id=$(qm list 2>/dev/null | awk 'NR>1 {print $1}' | sort -n | tail -1)
        max_lxc_id=$(pct list 2>/dev/null | awk 'NR>1 {print $1}' | sort -n | tail -1)

        # Find the maximum between VMs and LXCs
        if [ -n "$max_vm_id" ] && [ -n "$max_lxc_id" ]; then
            max_id=$((max_vm_id > max_lxc_id ? max_vm_id : max_lxc_id))
        elif [ -n "$max_vm_id" ]; then
            max_id=$max_vm_id
        elif [ -n "$max_lxc_id" ]; then
            max_id=$max_lxc_id
        else
            max_id=99
        fi
    fi

    # Ensure minimum VMID is 100 (Proxmox requirement)
    if [ -z "$max_id" ] || [ "$max_id" -lt 100 ]; then
        echo "100"
    else
        echo "$((max_id + 1))"
    fi
}

#-------------------------------------------------------------------------------
# Function: validate_vmid
# Description: Validates that a VMID is available in cluster/standalone
# Arguments:
#   $1 - vmid: VMID to validate
# Returns: 0 if available, 1 if in use
#-------------------------------------------------------------------------------
validate_vmid() {
    local vmid=$1

    # Check if in cluster or standalone
    if pvecm status &>/dev/null; then
        # Cluster mode - check across all nodes
        if pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | \
           jq -e ".[] | select(.vmid == $vmid)" &>/dev/null; then
            return 1  # VMID in use
        fi
    else
        # Standalone mode - check local VMs and LXCs
        if qm status "$vmid" &>/dev/null || pct status "$vmid" &>/dev/null; then
            return 1  # VMID in use
        fi
    fi

    return 0  # VMID available
}

#-------------------------------------------------------------------------------
# Function: get_vm_state
# Description: Gets detailed state of an existing VM
# Arguments:
#   $1 - vmid: VM ID to check
# Returns: JSON object with VM state information (stdout)
# Exit codes: 0 if VM exists, 1 if not
#-------------------------------------------------------------------------------
get_vm_state() {
    local vmid=$1

    # Check if VM exists
    if ! qm status "$vmid" &>/dev/null; then
        return 1
    fi

    # Get VM configuration
    local config
    config=$(qm config "$vmid" 2>/dev/null)

    # Parse state
    local has_efidisk=0
    local has_scsi0=0
    local has_cloudinit=0
    local has_boot_config=0
    local has_agent=0
    local vm_name=""

    if echo "$config" | grep -q "^efidisk0:"; then
        has_efidisk=1
    fi

    if echo "$config" | grep -q "^scsi0:"; then
        has_scsi0=1
    fi

    if echo "$config" | grep -q "^ide2:.*cloudinit"; then
        has_cloudinit=1
    fi

    if echo "$config" | grep -q "^boot:.*order=scsi0"; then
        has_boot_config=1
    fi

    if echo "$config" | grep -q "^agent:.*enabled=1"; then
        has_agent=1
    fi

    vm_name=$(echo "$config" | grep "^name:" | cut -d: -f2 | xargs)

    # Output JSON
    cat <<EOF
{
    "exists": true,
    "vmid": $vmid,
    "name": "$vm_name",
    "has_efidisk": $has_efidisk,
    "has_scsi0": $has_scsi0,
    "has_cloudinit": $has_cloudinit,
    "has_boot_config": $has_boot_config,
    "has_agent": $has_agent,
    "is_complete": $((has_efidisk && has_scsi0 && has_cloudinit && has_boot_config))
}
EOF

    return 0
}

#-------------------------------------------------------------------------------
# Function: set_vm_tags
# Description: Sets or updates tags on a VM (idempotent)
# Arguments:
#   $1 - vmid: VM ID
#   $2+ - tags: Tags to set (semicolon-separated when passed as one arg)
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
set_vm_tags() {
    local vmid=$1
    shift
    local new_tags="$*"

    # If tags are passed as a single semicolon-separated string, use as-is
    # Otherwise, join multiple args with semicolons
    if [[ "$new_tags" == *";"* ]]; then
        # Already formatted with semicolons
        new_tags="${new_tags// /}"  # Remove spaces
    else
        # Join args with semicolons
        new_tags="${new_tags// /;}"
    fi

    # Get current tags
    local current_tags
    current_tags=$(qm config "$vmid" 2>/dev/null | grep "^tags:" | cut -d: -f2 | xargs || echo "")

    # Compare and set only if different
    if [ "$current_tags" = "$new_tags" ]; then
        log_step "Tags already set: $new_tags" "SKIP" >&2
        return 0
    fi

    # Set tags (capture error output)
    local error_output
    if error_output=$(qm set "$vmid" --tags "$new_tags" 2>&1); then
        log_step "Tags set: $new_tags" "SUCCESS" >&2
        return 0
    else
        log_step "Failed to set tags: $error_output" "WARN" >&2
        # Don't fail the whole process, just warn
        return 0
    fi
}

#-------------------------------------------------------------------------------
# Function: add_vm_tag
# Description: Adds a tag to existing VM tags without removing others (idempotent)
# Arguments:
#   $1 - vmid: VM ID
#   $2 - tag: Tag to add
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
add_vm_tag() {
    local vmid=$1
    local new_tag=$2

    # Get current tags
    local current_tags
    current_tags=$(qm config "$vmid" 2>/dev/null | grep "^tags:" | cut -d: -f2 | xargs || echo "")

    # Check if tag already exists
    if [[ ";${current_tags};" == *";${new_tag};"* ]]; then
        log_step "Tag '$new_tag' already exists" "SKIP" >&2
        return 0
    fi

    # Add new tag
    local updated_tags
    if [ -z "$current_tags" ]; then
        updated_tags="$new_tag"
    else
        updated_tags="${current_tags};${new_tag}"
    fi

    # Set updated tags (capture error output)
    local error_output
    if error_output=$(qm set "$vmid" --tags "$updated_tags" 2>&1); then
        log_step "Tag added: $new_tag" "SUCCESS" >&2
        return 0
    else
        log_step "Failed to add tag: $error_output" "WARN" >&2
        # Don't fail the whole process, just warn
        return 0
    fi
}

#-------------------------------------------------------------------------------
# Function: create_vm
# Description: Creates a new VM with Q35 + EFI configuration (idempotent)
# Arguments:
#   $1 - vmid: VM ID
#   $2 - name: VM name
#   $3 - cores: CPU cores
#   $4 - memory: Memory in MB
#   $5 - storage: Storage name
#   $6 - os_key: OS key for OS-specific adjustments (optional)
# Returns: 0 on success, 1 on failure
# Globals: VM_FORCE_RECREATE - if set to 1, destroys and recreates existing VM
#-------------------------------------------------------------------------------
create_vm() {
    local vmid=$1
    local name=$2
    local cores=$3
    local memory=$4
    local storage=$5
    local os_key=${6:-}

    # Check NUMA support once if not already checked
    if [ -z "${NUMA_CHECKED:-}" ]; then
        check_numa_support
        export NUMA_CHECKED=1
    fi

    # Check if VM already exists
    if qm status "$vmid" &>/dev/null; then
        log_step "VM $vmid already exists" "INFO"

        # If force recreate is enabled, destroy and recreate
        if [ "${VM_FORCE_RECREATE:-0}" -eq 1 ]; then
            log_step "Force recreate enabled, destroying existing VM $vmid" "WARN"

            # Stop VM if running
            local vm_status
            vm_status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')
            if [ "$vm_status" = "running" ]; then
                log_step "Stopping VM $vmid" "INFO"
                qm stop "$vmid" || true
                sleep 3
            fi

            # Destroy VM
            qm destroy "$vmid" || {
                log_step "Failed to destroy VM $vmid" "FAILED"
                return 1
            }
            log_step "VM $vmid destroyed" "SUCCESS"
        else
            # VM exists and not forcing recreate - check state
            local vm_state
            vm_state=$(get_vm_state "$vmid")
            local is_complete
            is_complete=$(echo "$vm_state" | jq -r '.is_complete')

            if [ "$is_complete" -eq 1 ]; then
                log_step "VM $vmid is already fully configured, skipping creation" "SKIP"
                return 0
            else
                log_step "VM $vmid exists but is incomplete, continuing configuration" "INFO"
                return 0
            fi
        fi
    fi

    log_step "Creating VM $vmid with Q35 and EFI" "INFO"

    # Determine NUMA value based on host support
    local numa_value="${NUMA_SUPPORTED:-0}"
    if [ "$numa_value" -eq 1 ]; then
        log_step "NUMA support detected, enabling for VM" "INFO"
    fi

    # Adjust machine type for OS-specific compatibility
    local machine_type="${VM_MACHINE_TYPE}"
    if [[ "$os_key" == debian* ]]; then
        # Debian has issues with viommu, use plain Q35
        machine_type="q35"
        log_step "Debian detected: using Q35 without viommu for compatibility" "INFO"
    fi

    # Create VM with configuration
    qm create "$vmid" \
        --name "$name" \
        --machine "$machine_type" \
        --bios "${VM_BIOS}" \
        --cpu "${VM_CPU_TYPE}" \
        --cores "$cores" \
        --memory "$memory" \
        --numa "$numa_value" \
        --net0 "${VM_NETWORK_MODEL},bridge=${DEFAULT_BRIDGE}" \
        --scsihw "${VM_SCSI_CONTROLLER}" \
        --vga "${VM_VGA}" \
        --ostype "${VM_OSTYPE}" || return 1

    log_step "VM $vmid created" "SUCCESS"

    # Add EFI disk
    log_step "Adding EFI disk" "INFO"
    qm set "$vmid" --efidisk0 "${storage}:${VM_EFI_SIZE},efitype=${VM_EFI_TYPE},pre-enrolled-keys=${VM_EFI_PRE_ENROLLED_KEYS}" || return 1
    log_step "EFI disk added" "SUCCESS"

    # Add OS tag if os_key is provided
    if [ -n "$os_key" ]; then
        log_step "Adding OS tag: $os_key" "INFO"
        set_vm_tags "$vmid" "$os_key"
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Function: import_disk
# Description: Imports a disk image to VM (idempotent)
# Arguments:
#   $1 - vmid: VM ID
#   $2 - image_file: Path to image file
#   $3 - storage: Storage name
#   $4 - disk_size: Disk size in GB
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
import_disk() {
    local vmid=$1
    local image_file=$2
    local storage=$3
    local disk_size=$4

    # Check if disk already exists
    if qm config "$vmid" 2>/dev/null | grep -q "^scsi0:"; then
        log_step "Disk already attached to VM $vmid, skipping import" "SKIP"

        # Check if resize is needed
        local current_size
        current_size=$(qm config "$vmid" | grep "^scsi0:" | grep -oP 'size=\K[0-9]+G' || echo "")

        if [ -n "$current_size" ] && [ "$current_size" != "${disk_size}G" ]; then
            log_step "Current disk size ($current_size) differs from requested (${disk_size}G)" "INFO"
            log_step "To resize, use: qm resize $vmid scsi0 ${disk_size}G" "INFO"
        fi

        return 0
    fi

    log_step "Importing disk image" "INFO"

    # Import disk image
    local import_output
    import_output=$(qm disk import "$vmid" "$image_file" "$storage" --format qcow2 2>&1)

    # Extract the disk name from import output
    local disk_name
    disk_name=$(echo "$import_output" | grep -oP "vm-${vmid}-disk-\d+" | head -1)

    if [ -z "$disk_name" ]; then
        log_step "Could not determine imported disk name" "FAILED"
        echo "$import_output" >&2
        return 1
    fi

    log_step "Disk imported as: $disk_name" "INFO"

    # Attach disk with performance options (without size parameter)
    # Add iothread and ssd emulation for better performance
    qm set "$vmid" --scsi0 "${storage}:${disk_name},iothread=1,ssd=1,discard=on" || return 1
    log_step "Disk attached to VM" "SUCCESS"

    # Resize disk to requested size
    qm disk resize "$vmid" scsi0 "${disk_size}G" || return 1
    log_step "Disk resized to ${disk_size}GB" "SUCCESS"

    return 0
}

#-------------------------------------------------------------------------------
# Function: configure_vm_boot
# Description: Configures VM boot order and console (idempotent)
# Arguments:
#   $1 - vmid: VM ID
#   $2 - storage: Storage name
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
configure_vm_boot() {
    local vmid=$1
    local storage=$2
    local config
    config=$(qm config "$vmid" 2>/dev/null)

    # Add cloud-init drive (idempotent check)
    if ! echo "$config" | grep -q "^ide2:.*cloudinit"; then
        log_step "Adding cloud-init drive" "INFO"
        qm set "$vmid" --ide2 "${storage}:cloudinit" || return 1
        log_step "Cloud-init drive added" "SUCCESS"
    else
        log_step "Cloud-init drive already configured" "SKIP"
    fi

    # Configure boot order (idempotent check)
    if ! echo "$config" | grep -q "^boot:.*order=scsi0"; then
        log_step "Configuring boot order" "INFO"
        qm set "$vmid" --boot order=scsi0 --bootdisk scsi0 || return 1
        qm set "$vmid" --serial0 socket --vga serial0 || return 1
        log_step "Boot configuration completed" "SUCCESS"
    else
        log_step "Boot order already configured" "SKIP"
    fi

    # Enable QEMU guest agent (idempotent check)
    if ! echo "$config" | grep -q "^agent:.*enabled=1"; then
        log_step "Enabling QEMU guest agent" "INFO"
        qm set "$vmid" --agent "enabled=${VM_AGENT_ENABLED},fstrim_cloned_disks=${VM_AGENT_FSTRIM}" || return 1
        log_step "QEMU guest agent enabled" "SUCCESS"
    else
        log_step "QEMU guest agent already enabled" "SKIP"
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Function: configure_cloud_init
# Description: Configures cloud-init for VM (idempotent)
# Arguments:
#   $1 - vmid: VM ID
#   $2 - username: Cloud-init user
#   $3 - ssh_key_path: Path to SSH public key
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
configure_cloud_init() {
    local vmid=$1
    local username=$2
    local ssh_key_path=$3
    local config
    config=$(qm config "$vmid" 2>/dev/null)

    # Check if cloud-init user is already set
    local current_user
    current_user=$(echo "$config" | grep "^ciuser:" | cut -d: -f2 | xargs)

    if [ -n "$current_user" ]; then
        if [ "$current_user" = "$username" ]; then
            log_step "Cloud-init user already set to: $username" "SKIP"
        else
            log_step "Updating cloud-init user from '$current_user' to '$username'" "INFO"
            qm set "$vmid" --ciuser "$username" || return 1
        fi
    else
        log_step "Setting cloud-init user: $username" "INFO"
        qm set "$vmid" --ciuser "$username" || return 1
    fi

    # SSH keys - always update (safe to do)
    log_step "Configuring SSH key" "INFO"
    qm set "$vmid" --sshkeys "$ssh_key_path" || return 1
    log_step "SSH key configured" "SUCCESS"

    # Configure network (DHCP) - idempotent check
    if ! echo "$config" | grep -q "^ipconfig0:.*ip=dhcp"; then
        log_step "Configuring network (DHCP)" "INFO"
        qm set "$vmid" --ipconfig0 ip=dhcp || return 1
    else
        log_step "Network already configured for DHCP" "SKIP"
    fi

    # Enable cloud-init updates - always set (idempotent)
    qm set "$vmid" --ciupgrade 1 || return 1

    log_step "Cloud-init configured" "SUCCESS"
    return 0
}

#-------------------------------------------------------------------------------
# Function: wait_for_vm_ip
# Description: Waits for VM to get an IP address via QEMU agent or ARP table
# Arguments:
#   $1 - vmid: VM ID
#   $2 - max_wait: Maximum wait time in seconds (default: 300)
# Returns: IP address on stdout, 1 on failure
#-------------------------------------------------------------------------------
wait_for_vm_ip() {
    local vmid=$1
    local max_wait=${2:-300}
    local vm_ip=""
    local elapsed=0
    local mac_address=""

    log_step "Waiting for VM to get IP address" "INFO" >&2

    # Get VM MAC address and bridge from config
    mac_address=$(qm config "$vmid" | grep -oP 'net0.*virtio=\K([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -1)
    local bridge_name
    bridge_name=$(qm config "$vmid" | grep -oP 'net0.*bridge=\K[^,]+' | head -1)

    if [ -n "$mac_address" ]; then
        log_step "VM MAC address: $mac_address" "INFO" >&2
    fi

    # Detect bridge broadcast address for ARP refresh
    local broadcast_addr=""
    if [ -n "$bridge_name" ]; then
        broadcast_addr=$(ip -4 addr show "$bridge_name" 2>/dev/null | grep -oP 'inet [0-9.]+/[0-9]+ brd \K[0-9.]+' | head -1)
        if [ -n "$broadcast_addr" ]; then
            log_step "Bridge $bridge_name broadcast: $broadcast_addr" "INFO" >&2
        fi
    fi

    while [ -z "$vm_ip" ] && [ "$elapsed" -lt "$max_wait" ]; do
        sleep 5
        elapsed=$((elapsed + 5))

        # Refresh ARP table using only standard tools (ping)
        if [ "$((elapsed % 5))" -eq 0 ] && [ -n "$bridge_name" ]; then
            # Get bridge network and do a quick subnet scan
            local bridge_ip
            bridge_ip=$(ip -4 addr show "$bridge_name" 2>/dev/null | grep -oP 'inet \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

            if [ -n "$bridge_ip" ]; then
                # Fast parallel ping of common IPs in subnet to populate ARP
                local subnet="${bridge_ip%.*}"
                # Ping gateway and first 20 IPs (most VMs get low IPs from DHCP)
                for i in 1 2 3 4 5 10 20 30 40 50 100 150 200 254; do
                    ( ping -c 1 -W 1 "${subnet}.${i}" &>/dev/null & )
                done
            fi
        fi

        # Method 1: Try to get IP from QEMU agent (preferred if available)
        vm_ip=$(qm guest cmd "$vmid" network-get-interfaces 2>/dev/null | \
                jq -r '.[] | select(.name != "lo") | .["ip-addresses"][] | select(.["ip-address-type"] == "ipv4") | .["ip-address"]' 2>/dev/null | head -1)

        # Method 2: If guest agent doesn't work, try ARP table using MAC address
        if [ -z "$vm_ip" ] && [ -n "$mac_address" ]; then
            # Debug: show what we find in ARP for this MAC
            if [ "$((elapsed % 30))" -eq 0 ] && [ "$elapsed" -gt 0 ]; then
                local arp_entry
                arp_entry=$(ip neigh | grep -i "$mac_address" || echo "No ARP entry found")
                log_step "ARP table check: $arp_entry" "INFO" >&2
            fi

            # Get IPv4 address only (filter out IPv6 and link-local)
            vm_ip=$(ip neigh | grep -i "$mac_address" | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        fi

        # Method 3: Check DHCP leases file (if using dnsmasq or similar)
        if [ -z "$vm_ip" ] && [ -n "$mac_address" ]; then
            # Common DHCP lease file locations
            for lease_file in /var/lib/misc/dnsmasq.leases /var/lib/dhcp/dhcpd.leases /var/lib/dnsmasq/dnsmasq.leases; do
                if [ -f "$lease_file" ]; then
                    vm_ip=$(grep -i "$mac_address" "$lease_file" 2>/dev/null | awk '{print $3}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
                    if [ -n "$vm_ip" ]; then
                        break
                    fi
                fi
            done
        fi

        # Method 4: Force ARP lookup by pinging specific IP ranges aggressively
        if [ -z "$vm_ip" ] && [ "$elapsed" -eq 35 ] && [ -n "$bridge_name" ]; then
            log_step "Performing aggressive ARP scan..." "INFO" >&2
            local bridge_ip
            bridge_ip=$(ip -4 addr show "$bridge_name" 2>/dev/null | grep -oP 'inet \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            if [ -n "$bridge_ip" ]; then
                local subnet="${bridge_ip%.*}"
                # Ping ALL IPs in subnet (aggressive one-time scan)
                for i in {1..254}; do
                    ping -c 1 -W 1 "${subnet}.${i}" &>/dev/null &
                done
                wait
                # Give ARP table time to update
                sleep 2
                # Try ARP lookup again
                vm_ip=$(ip neigh | grep -i "$mac_address" | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
            fi
        fi

        if [ -n "$vm_ip" ]; then
            log_step "VM IP address found: $vm_ip" "SUCCESS" >&2
            break
        fi

        # Show progress every 30 seconds
        if [ $((elapsed % 30)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
            log_step "Still waiting for IP... (${elapsed}s elapsed)" "INFO" >&2
        fi

        echo -n "." >&2
    done
    echo "" >&2

    if [ -z "$vm_ip" ]; then
        log_step "Could not get VM IP address after ${max_wait}s" "FAILED" >&2
        log_step "Verify: 1) VM has network, 2) qemu-guest-agent is installed" "INFO" >&2
        return 1
    fi

    echo "$vm_ip"
    return 0
}

#-------------------------------------------------------------------------------
# Function: wait_for_ssh
# Description: Waits for SSH to be ready on VM
# Arguments:
#   $1 - ip_address: VM IP address
#   $2 - username: SSH username
#   $3 - ssh_key: Path to SSH private key
#   $4 - max_wait: Maximum wait time in seconds (default: 180)
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
wait_for_ssh() {
    local ip_address=$1
    local username=$2
    local ssh_key=$3
    local max_wait=${4:-180}
    local elapsed=0

    log_step "Waiting for SSH to be ready" "INFO" >&2

    while [ "$elapsed" -lt "$max_wait" ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$ssh_key" \
               "${username}@${ip_address}" "echo 'SSH OK'" &>/dev/null; then
            log_step "SSH connection successful" "SUCCESS" >&2
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "." >&2
    done
    echo "" >&2

    log_step "SSH connection failed after ${max_wait}s" "FAILED" >&2
    return 1
}

#-------------------------------------------------------------------------------
# Function: wait_for_cloud_init
# Description: Waits for cloud-init to complete on VM
# Arguments:
#   $1 - ip_address: VM IP address
#   $2 - username: SSH username
#   $3 - ssh_key: Path to SSH private key
#   $4 - max_wait: Maximum wait time in seconds (default: 600)
# Returns: 0 on success, 1 on timeout
#-------------------------------------------------------------------------------
wait_for_cloud_init() {
    local ip_address=$1
    local username=$2
    local ssh_key=$3
    local max_wait=${4:-600}
    local elapsed=0
    local status=""

    log_step "Waiting for cloud-init to complete" "INFO" >&2

    while [ "$elapsed" -lt "$max_wait" ]; do
        # Check cloud-init status
        status=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$ssh_key" \
                 "${username}@${ip_address}" \
                 "cloud-init status 2>/dev/null || echo 'not-found'" 2>/dev/null)

        # Debug: show status on first check and every 60 seconds
        if [ "$elapsed" -eq 0 ] || [ $((elapsed % 60)) -eq 0 ]; then
            local status_line="${status%%$'\n'*}"
            log_step "Cloud-init check at ${elapsed}s: ${status_line:-no response}" "INFO" >&2
        fi

        # Check if cloud-init is done
        if echo "$status" | grep -q "status: done"; then
            log_step "Cloud-init completed successfully (took ${elapsed}s)" "SUCCESS" >&2
            return 0
        fi

        # Check if cloud-init is disabled or not running
        if echo "$status" | grep -q "status: disabled"; then
            log_step "Cloud-init is disabled, skipping" "INFO" >&2
            return 0
        fi

        # Check if cloud-init is not installed (some images don't have it)
        if echo "$status" | grep -q "not-found"; then
            log_step "Cloud-init not found or not installed, skipping" "INFO" >&2
            return 0
        fi

        # Check for error state
        if echo "$status" | grep -q "status: error"; then
            log_step "Cloud-init reported an error, continuing anyway" "WARN" >&2
            return 0  # Continue anyway
        fi

        sleep 5
        elapsed=$((elapsed + 5))

        # Show progress dot every 10 seconds
        if [ $((elapsed % 10)) -eq 0 ]; then
            echo -n "." >&2
        fi
    done
    echo "" >&2

    log_step "Cloud-init check timed out after ${max_wait}s, continuing anyway" "WARN" >&2
    return 0
}

#-------------------------------------------------------------------------------
# Function: install_qemu_agent
# Description: Installs qemu-guest-agent on the VM via SSH
# Arguments:
#   $1 - ip_address: VM IP address
#   $2 - username: SSH username
#   $3 - ssh_key: Path to SSH private key
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_qemu_agent() {
    local ip_address=$1
    local username=$2
    local ssh_key=$3

    log_step "Checking if qemu-guest-agent is installed" "INFO" >&2

    # Check if already installed and running
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$ssh_key" \
           "${username}@${ip_address}" "systemctl is-active qemu-guest-agent 2>/dev/null" | grep -q "active"; then
        log_step "qemu-guest-agent is already installed and running" "SUCCESS" >&2
        return 0
    fi

    # Check if installed but not running
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$ssh_key" \
           "${username}@${ip_address}" "which qemu-ga 2>/dev/null || which qemu-guest-agent 2>/dev/null" &>/dev/null; then
        log_step "qemu-guest-agent is installed but not running, starting it" "INFO" >&2
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$ssh_key" \
            "${username}@${ip_address}" "sudo systemctl start qemu-guest-agent 2>/dev/null || true" &>/dev/null
        log_step "qemu-guest-agent started" "SUCCESS" >&2
        return 0
    fi

    log_step "Installing qemu-guest-agent" "INFO" >&2

    # Detect OS
    local os_type
    os_type=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$ssh_key" \
                  "${username}@${ip_address}" \
                  "grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"'" 2>/dev/null)

    if [ -z "$os_type" ]; then
        log_step "Could not detect OS type, skipping agent installation" "WARN" >&2
        return 1
    fi

    log_step "Detected OS: $os_type" "INFO" >&2

    # Retry installation up to 3 times with increasing delays
    local install_result=1
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ] && [ $install_result -ne 0 ]; do
        if [ $attempt -gt 1 ]; then
            local delay=$((attempt * 10))
            log_step "Attempt $attempt/$max_attempts - Waiting ${delay}s for system to stabilize..." "INFO" >&2
            sleep "$delay"
        else
            log_step "Attempt $attempt/$max_attempts - Installing..." "INFO" >&2
        fi

        # Install based on OS
        case "$os_type" in
            ubuntu|debian)
                if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=120 -i "$ssh_key" \
                       "${username}@${ip_address}" \
                       "sudo apt-get update -qq 2>&1 && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent 2>&1 && sudo systemctl enable --now qemu-guest-agent 2>&1" >/dev/null 2>&1; then
                    install_result=0
                fi
                ;;
            rocky|rhel|centos|fedora|almalinux)
                if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=120 -i "$ssh_key" \
                       "${username}@${ip_address}" \
                       "sudo dnf install -y qemu-guest-agent 2>&1 || sudo yum install -y qemu-guest-agent 2>&1 && sudo systemctl enable --now qemu-guest-agent 2>&1" >/dev/null 2>&1; then
                    install_result=0
                fi
                ;;
            *)
                log_step "Unsupported OS type: $os_type" "WARN" >&2
                return 1
                ;;
        esac

        attempt=$((attempt + 1))
    done

    if [ $install_result -eq 0 ]; then
        log_step "qemu-guest-agent installed and started successfully" "SUCCESS" >&2
        return 0
    else
        log_step "Failed to install qemu-guest-agent after $max_attempts attempts (non-critical)" "WARN" >&2
        return 1
    fi
}

# Export functions for use in subshells
export -f check_numa_support
export -f generate_vmid
export -f validate_vmid
export -f get_vm_state
export -f set_vm_tags
export -f add_vm_tag
export -f create_vm
export -f import_disk
export -f configure_vm_boot
export -f configure_cloud_init
export -f wait_for_vm_ip
export -f wait_for_ssh
export -f wait_for_cloud_init
export -f install_qemu_agent
