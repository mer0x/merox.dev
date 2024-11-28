#!/bin/bash

# Funcție pentru verificarea și instalarea unui pachet
install_if_missing() {
    local package=$1
    if ! dpkg -l | grep -qw "$package"; then
        echo "$package nu este instalat. Se instalează..."
        apt update && apt install -y "$package"
    else
        echo "$package este deja instalat."
    fi
}

# Verificare și instalare sudo dacă lipsește
if ! command -v sudo &> /dev/null; then
    echo "sudo nu este instalat. Se instalează..."
    apt update && apt install -y sudo
else
    echo "sudo este deja instalat."
fi

# 1. Instalare Git și alte pachete esențiale
install_if_missing "git"
install_if_missing "curl"
install_if_missing "unzip"
install_if_missing "lsb-release"

# 2. Instalare Ansible
if ! command -v ansible &> /dev/null; then
    echo "Ansible nu este instalat. Se instalează..."
    sudo apt update
    sudo apt install -y software-properties-common
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt install -y ansible
else
    echo "Ansible este deja instalat."
fi

# 3. Instalare Terraform
if ! command -v terraform &> /dev/null; then
    echo "Terraform nu este instalat. Se instalează..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt install -y terraform
else
    echo "Terraform este deja instalat."
fi

# 4. Generare cheie SSH
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Generare cheie SSH..."
    ssh-keygen -t ed25519 -C "merox@homelab" -f "$SSH_KEY_PATH" -N ""
    echo "Cheia publică este:"
    cat "${SSH_KEY_PATH}.pub"
    echo "Adaugă cheia publică în GitHub, în secțiunea Deploy Keys:"
    cat "${SSH_KEY_PATH}.pub"
    echo "Apasă Enter după ce ai adăugat cheia în GitHub..."
    read -r
else
    echo "Cheia SSH există deja la $SSH_KEY_PATH."
fi

# 5. Verificare conexiune SSH cu GitHub
echo "Verific conexiunea SSH cu GitHub..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "Conexiunea SSH este funcțională."
else
    echo "Conexiunea SSH a eșuat. Verifică cheile SSH și permisiunile."
    exit 1
fi

# 6. Clonează repository-ul
REPO_URL="git@github.com:mer0x/homelab.git"
REPO_DIR="$HOME/homelab"
if [ ! -d "$REPO_DIR" ]; then
    echo "Clonare repository $REPO_URL în $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR"
else
    echo "Repository-ul există deja la $REPO_DIR."
fi

# 7. Rulează Terraform init și apply
TERRAFORM_DIR="$REPO_DIR/terraform/proxmox-lxc"
if [ -d "$TERRAFORM_DIR" ]; then
    echo "Navighez la $TERRAFORM_DIR..."
    cd "$TERRAFORM_DIR" || exit
    echo "Initializare Terraform..."
    terraform init
    echo "Aplic configurațiile Terraform..."
    terraform apply -auto-approve
else
    echo "Directorul Terraform $TERRAFORM_DIR nu există. Verifică repository-ul."
    exit 1
fi

echo "Proces complet! Terraform s-a ocupat și de Ansible."
