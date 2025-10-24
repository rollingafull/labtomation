#!/bin/bash

#===============================================================================
# Title: DevOps Tools Installation Library
# Description: Functions for installing Ansible, Terraform, Vault, and Jenkins
#-------------------------------------------------------------------------------
# Author: rolling (rolling@a-full.com)
# Created: 2025-10-20
# Updated: 2025-10-20
# Version: 2.0.0
#===============================================================================

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/common_lib.sh"

#-------------------------------------------------------------------------------
# Function: detect_package_manager
# Description: Detects the system package manager
# Returns: Package manager name (dnf, apt, yum, zypper)
#-------------------------------------------------------------------------------
detect_package_manager() {
    if command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    else
        echo "unknown"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: install_system_packages
# Description: Installs system packages using detected package manager
# Arguments:
#   $@ - List of packages to install
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_system_packages() {
    local packages=("$@")
    local pkg_mgr
    pkg_mgr=$(detect_package_manager)

    log_step "Installing system packages: ${packages[*]}" "START"

    case "$pkg_mgr" in
        dnf|yum)
            sudo "$pkg_mgr" install -y "${packages[@]}"
            ;;
        apt)
            sudo apt-get update
            sudo apt-get install -y "${packages[@]}"
            ;;
        zypper)
            sudo zypper install -y "${packages[@]}"
            ;;
        *)
            log_step "Unsupported package manager" "FAILED"
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        log_step "System packages installed" "SUCCESS"
        return 0
    else
        log_step "Failed to install system packages" "FAILED"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: install_ansible
# Description: Installs Ansible and common collections
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_ansible() {
    log_step "Installing Ansible" "START"

    # Check if already installed
    if command -v ansible &>/dev/null; then
        local version
        version=$(ansible --version | head -1 | awk '{print $3}')
        log_step "Ansible already installed" "SKIP" "version $version"
        return 0
    fi

    local pkg_mgr
    pkg_mgr=$(detect_package_manager)

    case "$pkg_mgr" in
        dnf|yum)
            sudo "$pkg_mgr" install -y ansible-core python3-pip
            ;;
        apt)
            sudo apt-get update
            sudo apt-get install -y software-properties-common
            sudo add-apt-repository --yes --update ppa:ansible/ansible
            sudo apt-get install -y ansible python3-pip
            ;;
        *)
            log_step "Installing Ansible via pip" "INFO"
            sudo pip3 install ansible
            ;;
    esac

    if ! command -v ansible &>/dev/null; then
        log_step "Ansible installation failed" "FAILED"
        return 1
    fi

    # Install common collections
    log_step "Installing Ansible collections" "INFO"
    ansible-galaxy collection install community.general --force
    ansible-galaxy collection install community.crypto --force
    ansible-galaxy collection install ansible.posix --force
    ansible-galaxy collection install community.docker --force

    # Install Proxmox collection
    ansible-galaxy collection install community.general.proxmox --force || true

    local version
    version=$(ansible --version | head -1 | awk '{print $3}')
    log_step "Ansible installed successfully" "SUCCESS" "version $version"

    return 0
}

#-------------------------------------------------------------------------------
# Function: install_terraform
# Description: Installs Terraform from HashiCorp releases
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_terraform() {
    log_step "Installing Terraform" "START"

    # Check if already installed
    if command -v terraform &>/dev/null; then
        local version
        version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | awk '{print $2}')
        log_step "Terraform already installed" "SKIP" "$version"
        return 0
    fi

    local terraform_version="${TERRAFORM_VERSION:-1.7.0}"
    local arch
    arch=$(uname -m)

    # Map architecture
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
    esac

    local download_url="https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_${arch}.zip"
    local temp_dir
    temp_dir=$(mktemp -d)

    log_step "Downloading Terraform $terraform_version" "INFO"

    if ! wget -q "$download_url" -O "$temp_dir/terraform.zip"; then
        log_step "Failed to download Terraform" "FAILED"
        rm -rf "$temp_dir"
        return 1
    fi

    # Install unzip if not present
    if ! command -v unzip &>/dev/null; then
        install_system_packages unzip
    fi

    unzip -q "$temp_dir/terraform.zip" -d "$temp_dir"
    sudo mv "$temp_dir/terraform" /usr/local/bin/
    sudo chmod +x /usr/local/bin/terraform

    rm -rf "$temp_dir"

    if command -v terraform &>/dev/null; then
        local version
        version=$(terraform version -json | jq -r '.terraform_version')
        log_step "Terraform installed successfully" "SUCCESS" "v$version"
        return 0
    else
        log_step "Terraform installation failed" "FAILED"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: install_vault
# Description: Installs HashiCorp Vault
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_vault() {
    log_step "Installing HashiCorp Vault" "START"

    # Check if already installed
    if command -v vault &>/dev/null; then
        local version
        version=$(vault version | head -1 | awk '{print $2}')
        log_step "Vault already installed" "SKIP" "$version"
        return 0
    fi

    local pkg_mgr
    pkg_mgr=$(detect_package_manager)

    case "$pkg_mgr" in
        dnf|yum)
            # Add HashiCorp repository
            sudo "$pkg_mgr" install -y dnf-plugins-core || sudo "$pkg_mgr" install -y yum-utils

            if [ "$pkg_mgr" = "dnf" ]; then
                sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
            else
                sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
            fi

            sudo "$pkg_mgr" install -y vault
            ;;
        apt)
            # Add HashiCorp GPG key and repository
            wget -O- https://apt.releases.hashicorp.com/gpg | \
                sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
                sudo tee /etc/apt/sources.list.d/hashicorp.list

            sudo apt-get update
            sudo apt-get install -y vault
            ;;
        *)
            log_step "Unsupported package manager for Vault" "FAILED"
            return 1
            ;;
    esac

    if command -v vault &>/dev/null; then
        local version
        version=$(vault version | head -1 | awk '{print $2}')
        log_step "Vault installed successfully" "SUCCESS" "$version"
        return 0
    else
        log_step "Vault installation failed" "FAILED"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: install_jenkins
# Description: Installs Jenkins LTS
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_jenkins() {
    log_step "Installing Jenkins" "START"

    # Check if already running
    if systemctl is-active --quiet jenkins 2>/dev/null; then
        local version
        version=$(sudo cat /var/lib/jenkins/config.xml 2>/dev/null | grep -oP '<version>\K[^<]+' || echo "unknown")
        log_step "Jenkins already installed and running" "SKIP" "version $version"
        return 0
    fi

    local pkg_mgr
    pkg_mgr=$(detect_package_manager)

    # Install Java first
    log_step "Installing Java (required for Jenkins)" "INFO"

    case "$pkg_mgr" in
        dnf|yum)
            sudo "$pkg_mgr" install -y java-17-openjdk java-17-openjdk-devel

            # Add Jenkins repository
            sudo wget -O /etc/yum.repos.d/jenkins.repo \
                https://pkg.jenkins.io/redhat-stable/jenkins.repo
            sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

            sudo "$pkg_mgr" install -y jenkins
            ;;
        apt)
            sudo apt-get install -y openjdk-17-jre openjdk-17-jdk

            # Add Jenkins repository
            sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
                https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

            echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
                sudo tee /etc/apt/sources.list.d/jenkins.list

            sudo apt-get update
            sudo apt-get install -y jenkins
            ;;
        *)
            log_step "Unsupported package manager for Jenkins" "FAILED"
            return 1
            ;;
    esac

    # Enable and start Jenkins
    log_step "Starting Jenkins service" "INFO"
    sudo systemctl daemon-reload
    sudo systemctl enable jenkins
    sudo systemctl start jenkins

    # Wait for Jenkins to start
    local max_wait=120
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if systemctl is-active --quiet jenkins; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done

    if ! systemctl is-active --quiet jenkins; then
        log_step "Jenkins service failed to start" "FAILED"
        return 1
    fi

    # Wait for initial admin password file
    sleep 10

    # Display initial admin password
    if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
        local initial_password
        initial_password=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

        log_step "Jenkins installed successfully" "SUCCESS"
        echo ""
        echo "================================================"
        echo "Jenkins Initial Setup Information"
        echo "================================================"
        echo "URL: http://$(hostname -I | awk '{print $1}'):8080"
        echo "Initial Admin Password: $initial_password"
        echo "================================================"
        echo ""
    else
        log_step "Jenkins installed but initial password not found" "WARN"
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Function: install_docker
# Description: Installs Docker CE
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_docker() {
    log_step "Installing Docker" "START"

    # Check if already installed
    if command -v docker &>/dev/null; then
        local version
        version=$(docker --version | awk '{print $3}' | tr -d ',')
        log_step "Docker already installed" "SKIP" "version $version"
        return 0
    fi

    local pkg_mgr
    pkg_mgr=$(detect_package_manager)

    case "$pkg_mgr" in
        dnf|yum)
            sudo "$pkg_mgr" install -y dnf-plugins-core || sudo "$pkg_mgr" install -y yum-utils
            sudo "$pkg_mgr" config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || \
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo "$pkg_mgr" install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        apt)
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings

            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
                sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg

            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        *)
            log_step "Unsupported package manager for Docker" "FAILED"
            return 1
            ;;
    esac

    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    # Add current user to docker group
    sudo usermod -aG docker "$(whoami)" || true

    if command -v docker &>/dev/null; then
        local version
        version=$(docker --version | awk '{print $3}' | tr -d ',')
        log_step "Docker installed successfully" "SUCCESS" "version $version"
        log_step "You may need to log out and back in for docker group membership to take effect" "INFO"
        return 0
    else
        log_step "Docker installation failed" "FAILED"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: install_git
# Description: Installs Git version control
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_git() {
    log_step "Installing Git" "START"

    # Check if already installed
    if command -v git &>/dev/null; then
        local version
        version=$(git --version | awk '{print $3}')
        log_step "Git already installed" "SKIP" "version $version"
        return 0
    fi

    install_system_packages git

    if command -v git &>/dev/null; then
        local version
        version=$(git --version | awk '{print $3}')
        log_step "Git installed successfully" "SUCCESS" "version $version"
        return 0
    else
        log_step "Git installation failed" "FAILED"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Function: install_common_tools
# Description: Installs common development and operations tools
# Returns: 0 on success, 1 on failure
#-------------------------------------------------------------------------------
install_common_tools() {
    log_step "Installing common tools" "START"

    local tools=(
        curl
        wget
        vim
        nano
        htop
        tmux
        screen
        net-tools
        bind-utils
        jq
        tree
        rsync
        ncdu
    )

    # Package name variations by distro
    local pkg_mgr
    pkg_mgr=$(detect_package_manager)

    if [ "$pkg_mgr" = "apt" ]; then
        # bind-utils is called dnsutils on Debian/Ubuntu
        tools=("${tools[@]/bind-utils/dnsutils}")
    fi

    install_system_packages "${tools[@]}"

    log_step "Common tools installed" "SUCCESS"
    return 0
}

#-------------------------------------------------------------------------------
# Function: install_all_devops_tools
# Description: Installs all DevOps tools in sequence
# Arguments:
#   $1 - skip_jenkins: Set to "true" to skip Jenkins (optional)
#   $2 - skip_docker: Set to "true" to skip Docker (optional)
# Returns: 0 if all successful, number of failures otherwise
#-------------------------------------------------------------------------------
install_all_devops_tools() {
    local skip_jenkins=${1:-false}
    local skip_docker=${2:-false}
    local failed=0

    log_step "Starting DevOps tools installation" "START"

    # Common tools
    install_common_tools || ((failed++))

    # Git
    install_git || ((failed++))

    # Ansible
    install_ansible || ((failed++))

    # Terraform
    install_terraform || ((failed++))

    # Vault
    install_vault || ((failed++))

    # Docker (optional)
    if [ "$skip_docker" != "true" ]; then
        install_docker || ((failed++))
    else
        log_step "Docker installation skipped" "SKIP"
    fi

    # Jenkins (optional)
    if [ "$skip_jenkins" != "true" ]; then
        install_jenkins || ((failed++))
    else
        log_step "Jenkins installation skipped" "SKIP"
    fi

    if [ $failed -eq 0 ]; then
        log_step "All DevOps tools installed successfully" "SUCCESS"
        return 0
    else
        log_step "$failed tool(s) failed to install" "WARN"
        return "$failed"
    fi
}

# Export functions
export -f install_ansible
export -f install_terraform
export -f install_vault
export -f install_jenkins
export -f install_docker
export -f install_git
export -f install_common_tools
export -f install_all_devops_tools
