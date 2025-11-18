#!/bin/bash

#############################################
# Mailcow Installation Script for Proxmox VM
#############################################

set -e

echo "========================================="
echo "Mailcow Installation Script"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Function to print colored messages
print_msg() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Update system
print_msg "Updating system packages..."
apt-get update && apt-get upgrade -y

# Install required packages
print_msg "Installing required packages..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    nano \
    wget

# Install Docker
print_msg "Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    print_msg "Docker installed successfully"
else
    print_msg "Docker is already installed"
fi

# Install Docker Compose (standalone)
print_msg "Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    print_msg "Docker Compose installed successfully"
else
    print_msg "Docker Compose is already installed"
fi

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Create directory for Mailcow
print_msg "Setting up Mailcow directory..."
MAILCOW_DIR="/opt/mailcow-dockerized"

if [ -d "$MAILCOW_DIR" ]; then
    print_warn "Mailcow directory already exists at $MAILCOW_DIR"
    read -p "Do you want to remove it and reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf $MAILCOW_DIR
    else
        print_error "Installation cancelled"
        exit 1
    fi
fi

# Clone Mailcow repository
print_msg "Cloning Mailcow repository..."
cd /opt
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized

# Prompt for mail server configuration
echo ""
echo "========================================="
echo "Mailcow Configuration"
echo "========================================="
echo ""

read -p "Enter your mail server hostname (e.g., mail.example.com): " MAILCOW_HOSTNAME
read -p "Enter your timezone (e.g., America/New_York): " MAILCOW_TZ

# Generate configuration
print_msg "Generating Mailcow configuration..."
./generate_config.sh

# Update mailcow.conf with user inputs
if [ ! -z "$MAILCOW_HOSTNAME" ]; then
    sed -i "s/^MAILCOW_HOSTNAME=.*/MAILCOW_HOSTNAME=$MAILCOW_HOSTNAME/" mailcow.conf
fi

if [ ! -z "$MAILCOW_TZ" ]; then
    sed -i "s/^TZ=.*/TZ=$MAILCOW_TZ/" mailcow.conf
fi

# Configure for reverse proxy setup
print_msg "Configuring Mailcow for reverse proxy..."

# Modify HTTP and HTTPS bind addresses to avoid conflicts with reverse proxy
sed -i 's/^HTTP_PORT=.*/HTTP_PORT=8080/' mailcow.conf
sed -i 's/^HTTPS_PORT=.*/HTTPS_PORT=8443/' mailcow.conf
sed -i 's/^HTTP_BIND=.*/HTTP_BIND=127.0.0.1/' mailcow.conf
sed -i 's/^HTTPS_BIND=.*/HTTPS_BIND=127.0.0.1/' mailcow.conf

# Set SKIP_LETS_ENCRYPT if using reverse proxy with its own SSL
sed -i 's/^SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=y/' mailcow.conf

# Enable SKIP_CLAMD if you want to save resources (optional)
# sed -i 's/^SKIP_CLAMD=.*/SKIP_CLAMD=y/' mailcow.conf

echo ""
print_msg "Configuration complete!"
print_msg "Review and edit /opt/mailcow-dockerized/mailcow.conf if needed"
echo ""

# Ask if user wants to start Mailcow now
read -p "Do you want to start Mailcow now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_msg "Starting Mailcow... This may take several minutes..."
    docker-compose pull
    docker-compose up -d

    echo ""
    print_msg "Mailcow is starting up..."
    print_msg "Web UI will be available at: https://$MAILCOW_HOSTNAME"
    print_msg "Default admin credentials:"
    print_msg "  Username: admin"
    print_msg "  Password: moohoo"
    print_msg ""
    print_warn "IMPORTANT: Change the default password after first login!"
    echo ""
    print_msg "To check status: docker-compose ps"
    print_msg "To view logs: docker-compose logs -f"
else
    print_msg "Mailcow installed but not started"
    print_msg "To start Mailcow later, run:"
    print_msg "  cd /opt/mailcow-dockerized"
    print_msg "  docker-compose up -d"
fi

echo ""
print_msg "Installation complete!"
print_msg "Next step: Configure Nginx reverse proxy on your proxy server"
echo ""
