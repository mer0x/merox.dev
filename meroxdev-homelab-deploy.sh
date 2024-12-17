#!/bin/bash

# Logo
echo -e "\n"
echo -e "\033[36;1m ██╗  ██╗ █████╗  ██████╗ \033[0m"
echo -e "\033[36;1m ██║  ██║██╔══██╗██╔════╝ \033[0m"
echo -e "\033[36;1m ███████║███████║██║      \033[0m"
echo -e "\033[36;1m ██╔══██║██╔══██║██║      \033[0m"
echo -e "\033[36;1m ██║  ██║██║  ██║╚██████╗ \033[0m"
echo -e "\033[36;1m ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ \033[0m"
echo -e "\033[36;1m                         \033[0m"
echo -e "\033[33;1m Homelab as Code by Merox.dev \033[0m"
echo -e "\n"

# Ensure sudo is installed without using sudo
if ! command -v sudo &> /dev/null; then
    echo "sudo is not installed. Installing..."
    apt update && apt install -y sudo
else
    echo "sudo is already installed."
fi

# Function to check and install a package if missing
install_if_missing() {
    local package=$1
    if ! dpkg -l | grep -qw "$package"; then
        echo "Installing $package..."
        sudo apt update && sudo apt install -y "$package"
    else
        echo "$package is already installed."
    fi
}

# Install essential packages
for package in git curl unzip lsb-release; do
    install_if_missing "$package"
done

# Install Ansible
if ! command -v ansible &> /dev/null; then
    echo "Installing Ansible..."
    export LC_ALL=C.UTF-8
    sudo apt update
    sudo apt install -y software-properties-common
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt install -y ansible
else
    echo "Ansible is already installed."
fi

# Install Terraform
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt install -y terraform
else
    echo "Terraform is already installed."
fi

# Install Packer
if ! command -v packer &> /dev/null; then
    echo "Installing Packer..."
    sudo apt install -y packer
else
    echo "Packer is already installed."
fi

# Ensure SSH configuration is set up
SSH_CONFIG_PATH="$HOME/.ssh/config"
if [ ! -f "$SSH_CONFIG_PATH" ]; then
    echo "Creating SSH configuration..."
    mkdir -p "$HOME/.ssh"
    cat <<EOL > "$SSH_CONFIG_PATH"
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOL
    chmod 400 "$SSH_CONFIG_PATH"
    echo "SSH configuration created and permissions set."
else
    echo "SSH configuration already exists."
fi

# Ask for repository type
echo -e "\e[33mWill you be using a Public or Private repository? (public/private): \e[0m"
read REPO_TYPE

# Prompt for repository link
echo -e "\e[33mPlease enter the repository link: \e[0m"
read REPO_URL

# Generate SSH key
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -C "merox@homelab" -f "$SSH_KEY_PATH" -N ""
    
    echo -e "\e[32mYour public key is:\e[0m"
    cat "${SSH_KEY_PATH}.pub"
    if [ "$REPO_TYPE" == "private" ]; then
        echo -e "\e[33mAdd the public key to GitHub under Deploy Keys and press Enter...\e[0m"
        read -r
    fi
else
    echo "SSH key already exists at $SSH_KEY_PATH."
fi

# Important Notes
echo -e "\e[32mPlease make sure to update the SSH public key in the following files:\e[0m"
echo -e "\e[32m- /home/homelab/terraform/modules/docker_vm/main_tf (replace YOUR_SSH_PUBLIC_KEY)\e[0m"
echo -e "\e[32m- /home/homelab/packer/ubuntu-server-jammy-docker/http/user-data (update ssh_authorized_keys: - ssh-rsa)\e[0m"

# Test SSH connection to GitHub for private repositories
if [ "$REPO_TYPE" == "private" ]; then
    echo "Testing SSH connection to GitHub..."
    if ssh -o StrictHostKeyChecking=no -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        echo "SSH connection is functional."
    else
        echo "SSH connection failed. Check your SSH keys and permissions."
        exit 1
    fi
fi

# Clone the repository
REPO_DIR="/home/homelab"
if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning repository $REPO_URL into $REPO_DIR..."
    if [ "$REPO_TYPE" == "private" ]; then
        GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git clone "$REPO_URL" "$REPO_DIR"
    else
        git clone "$REPO_URL" "$REPO_DIR"
    fi
else
    echo "Repository already exists at $REPO_DIR."
fi

# Ask if the user has edited the specific files
echo -e "\e[33mHave you edited the specific files declared in the tutorial?\n(Visit: \e[36mhttps://merox.dev/blog/homelab-as-code\e[33m)\e[0m"
read -p "(yes/no): " EDITED_FILES

if [ "$EDITED_FILES" != "yes" ]; then
    echo "Please edit the specific files declared in the tutorial before proceeding."
    exit 0
fi

# Ask for deployment type (LXC or VM)
echo -e "\e[33mDo you want to deploy to LXC or VM? (lxc/vm): \e[0m"
read DEPLOY_TYPE

if [ "$DEPLOY_TYPE" == "lxc" ]; then
    # Run Terraform init and apply
    TERRAFORM_DIR="$REPO_DIR/terraform/"
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
elif [ "$DEPLOY_TYPE" == "vm" ]; then
    # Initialize Packer and build VM
    echo "Navigating to /home/homelab/packer..."
    cd /home/homelab/packer || exit
    echo "Initializing Packer..."
    packer init packer.pkr.hcl
    echo "Navigating to ubuntu-server-jammy-docker directory..."
    cd ubuntu-server-jammy-docker || exit
    echo "Validating Packer template..."
    packer validate -var-file='../credentials.pkr.hcl' ./ubuntu-server-jammy-docker.pkr.hcl
    echo "Building VM with Packer..."
    packer build -var-file='../credentials.pkr.hcl' ./ubuntu-server-jammy-docker.pkr.hcl
else
    echo "Invalid deployment type selected. Please choose either 'lxc' or 'vm'."
    exit 1
fi

echo "Process complete! Visit www.merox.dev for more :)."
