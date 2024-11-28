#!/bin/bash

# Function to check and install a package if missing
install_if_missing() {
    local package=$1
    if ! dpkg -l | grep -qw "$package"; then
        echo "$package is not installed. Installing..."
        apt update && apt install -y "$package"
    else
        echo "$package is already installed."
    fi
}

# Check and install sudo if missing
if ! command -v sudo &> /dev/null; then
    echo "sudo is not installed. Installing..."
    apt update && apt install -y sudo
else
    echo "sudo is already installed."
fi

# 1. Install Git and other essential packages
install_if_missing "git"
install_if_missing "curl"
install_if_missing "unzip"
install_if_missing "lsb-release"

# 2. Install Ansible
if ! command -v ansible &> /dev/null; then
    echo "Ansible is not installed. Installing..."
    sudo apt update
    sudo apt install -y software-properties-common
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt install -y ansible
else
    echo "Ansible is already installed."
fi

# 3. Install Terraform
if ! command -v terraform &> /dev/null; then
    echo "Terraform is not installed. Installing..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt install -y terraform
else
    echo "Terraform is already installed."
fi

# 4. Generate SSH key
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -C "merox@homelab" -f "$SSH_KEY_PATH" -N ""
    echo "Your public key is:"
    cat "${SSH_KEY_PATH}.pub"
    echo "Add the public key to GitHub under Deploy Keys:"
    echo "Press Enter once you've added the key to GitHub..."
    read -r
else
    echo "SSH key already exists at $SSH_KEY_PATH."
fi

# 5. Test SSH connection to GitHub
echo "Testing SSH connection to GitHub..."
if ssh -o StrictHostKeyChecking=no -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "SSH connection is functional."
else
    echo "SSH connection failed. Check your SSH keys and permissions."
    exit 1
fi

# 6. Clone the repository
REPO_URL="git@github.com:mer0x/homelab.git"
REPO_DIR="/home/homelab"
if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning repository $REPO_URL into $REPO_DIR..."
    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git clone "$REPO_URL" "$REPO_DIR"
else
    echo "Repository already exists at $REPO_DIR."
fi

# 7. Run Terraform init and apply
TERRAFORM_DIR="$REPO_DIR/terraform/proxmox-lxc"
if [ -d "$TERRAFORM_DIR" ]; then
    echo "Navigating to $TERRAFORM_DIR..."
    cd "$TERRAFORM_DIR" || exit
    echo "Initializing Terraform..."
    terraform init
    echo "Applying Terraform configuration..."
    terraform apply -auto-approve
else
    echo "Terraform directory $TERRAFORM_DIR does not exist. Check the repository."
    exit 1
fi

echo "Process complete! Terraform has also taken care of Ansible."
