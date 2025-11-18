#!/bin/bash

#############################################
# Add Mailcow Configuration to Existing Nginx
# Run this on your existing Nginx proxy server (192.168.0.9)
#############################################

set -e

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

echo "========================================="
echo "Add Mailcow to Existing Nginx Proxy"
echo "========================================="
echo ""

# Prompt for configuration
read -p "Enter your Mailcow VM IP address: " MAILCOW_IP
read -p "Enter your mail server hostname (e.g., mail.example.com): " MAIL_HOSTNAME
read -p "Enter your base domain (e.g., example.com): " BASE_DOMAIN

# Validate inputs
if [ -z "$MAILCOW_IP" ] || [ -z "$MAIL_HOSTNAME" ] || [ -z "$BASE_DOMAIN" ]; then
    print_error "All inputs are required!"
    exit 1
fi

print_warn "This will add Mailcow configuration to your existing Nginx setup"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Installation cancelled"
    exit 1
fi

# Check if Certbot is installed
if ! command -v certbot &> /dev/null; then
    print_msg "Installing Certbot for SSL certificates..."
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
fi

# Generate SSL certificate
print_msg "Generating SSL certificate for $MAIL_HOSTNAME..."
print_warn "Make sure DNS records for $MAIL_HOSTNAME, autodiscover.$BASE_DOMAIN, and autoconfig.$BASE_DOMAIN point to this server!"
read -p "Press Enter to continue or Ctrl+C to abort..."

# Stop Nginx temporarily for certificate generation
systemctl stop nginx

certbot certonly --standalone -d $MAIL_HOSTNAME -d autodiscover.$BASE_DOMAIN -d autoconfig.$BASE_DOMAIN

# Start Nginx again
systemctl start nginx

# Create Nginx sites directories if they don't exist
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
mkdir -p /var/www/html/.well-known/acme-challenge

# Create HTTP/HTTPS reverse proxy configuration
print_msg "Creating Mailcow Nginx configuration..."
cat > /etc/nginx/sites-available/mailcow << EOF
##############################################
# Mailcow Reverse Proxy Configuration
# Generated: $(date)
##############################################

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $MAIL_HOSTNAME autodiscover.$BASE_DOMAIN autoconfig.$BASE_DOMAIN;

    # Allow Let's Encrypt verification
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    # Redirect everything else to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS - Mailcow Web UI and SOGo
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $MAIL_HOSTNAME;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$MAIL_HOSTNAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIL_HOSTNAME/privkey.pem;

    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logging
    access_log /var/log/nginx/mailcow-access.log;
    error_log /var/log/nginx/mailcow-error.log;

    # Client upload size (for attachments)
    client_max_body_size 50M;

    # Proxy settings
    location / {
        proxy_pass http://$MAILCOW_IP:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support for SOGo
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
    }
}

# Autodiscover - Microsoft Outlook
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name autodiscover.$BASE_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MAIL_HOSTNAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIL_HOSTNAME/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://$MAILCOW_IP:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Autoconfig - Thunderbird
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name autoconfig.$BASE_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MAIL_HOSTNAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIL_HOSTNAME/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://$MAILCOW_IP:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/mailcow /etc/nginx/sites-enabled/

# Backup original nginx.conf
if [ ! -f /etc/nginx/nginx.conf.mailcow-backup ]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.mailcow-backup
    print_msg "Backed up nginx.conf to nginx.conf.mailcow-backup"
fi

# Check if stream directive already exists
if ! grep -q "^stream {" /etc/nginx/nginx.conf; then
    print_msg "Adding stream configuration for mail protocols..."

    # Add stream configuration to nginx.conf
    cat >> /etc/nginx/nginx.conf << 'EOF'

##############################################
# Mail Protocol Stream Configuration
# Added by Mailcow setup script
##############################################

stream {
    log_format proxy '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time "$upstream_addr" '
                     '"$upstream_bytes_sent" "$upstream_bytes_received" "$upstream_connect_time"';

    access_log /var/log/nginx/mail-stream-access.log proxy;
    error_log /var/log/nginx/mail-stream-error.log;

EOF

    # Add each mail protocol proxy
    cat >> /etc/nginx/nginx.conf << EOF
    # SMTP - Port 25 (Incoming mail)
    server {
        listen 25;
        listen [::]:25;
        proxy_pass $MAILCOW_IP:25;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # SMTP Submission - Port 587 (Outgoing mail with STARTTLS)
    server {
        listen 587;
        listen [::]:587;
        proxy_pass $MAILCOW_IP:587;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # SMTPS - Port 465 (Outgoing mail with SSL)
    server {
        listen 465;
        listen [::]:465;
        proxy_pass $MAILCOW_IP:465;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # IMAP - Port 143 (with STARTTLS)
    server {
        listen 143;
        listen [::]:143;
        proxy_pass $MAILCOW_IP:143;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # IMAPS - Port 993 (with SSL)
    server {
        listen 993;
        listen [::]:993;
        proxy_pass $MAILCOW_IP:993;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # POP3 - Port 110 (with STARTTLS)
    server {
        listen 110;
        listen [::]:110;
        proxy_pass $MAILCOW_IP:110;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # POP3S - Port 995 (with SSL)
    server {
        listen 995;
        listen [::]:995;
        proxy_pass $MAILCOW_IP:995;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # Sieve - Port 4190 (ManageSieve)
    server {
        listen 4190;
        listen [::]:4190;
        proxy_pass $MAILCOW_IP:4190;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }
}
EOF
    print_msg "Stream configuration added successfully"
else
    print_warn "Stream configuration already exists in nginx.conf"
    print_warn "You'll need to manually add the mail protocol proxies"
    print_warn "Configuration template saved to /tmp/mailcow-stream.conf"

    cat > /tmp/mailcow-stream.conf << EOF
# Add these server blocks inside your existing stream { } block:

    # SMTP - Port 25 (Incoming mail)
    server {
        listen 25;
        listen [::]:25;
        proxy_pass $MAILCOW_IP:25;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # SMTP Submission - Port 587
    server {
        listen 587;
        listen [::]:587;
        proxy_pass $MAILCOW_IP:587;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # SMTPS - Port 465
    server {
        listen 465;
        listen [::]:465;
        proxy_pass $MAILCOW_IP:465;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # IMAP - Port 143
    server {
        listen 143;
        listen [::]:143;
        proxy_pass $MAILCOW_IP:143;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # IMAPS - Port 993
    server {
        listen 993;
        listen [::]:993;
        proxy_pass $MAILCOW_IP:993;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # POP3 - Port 110
    server {
        listen 110;
        listen [::]:110;
        proxy_pass $MAILCOW_IP:110;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # POP3S - Port 995
    server {
        listen 995;
        listen [::]:995;
        proxy_pass $MAILCOW_IP:995;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # Sieve - Port 4190
    server {
        listen 4190;
        listen [::]:4190;
        proxy_pass $MAILCOW_IP:4190;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }
EOF
fi

# Test Nginx configuration
print_msg "Testing Nginx configuration..."
if nginx -t; then
    print_msg "Nginx configuration is valid"
else
    print_error "Nginx configuration has errors!"
    print_error "Restoring backup configuration..."
    cp /etc/nginx/nginx.conf.mailcow-backup /etc/nginx/nginx.conf
    exit 1
fi

# Reload Nginx
systemctl reload nginx

# Setup automatic SSL renewal if not already configured
if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
    print_msg "Setting up automatic SSL renewal..."
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
fi

echo ""
echo "========================================="
print_msg "Mailcow Configuration Added Successfully!"
echo "========================================="
echo ""
print_msg "Configuration Summary:"
echo "  Mail Server: $MAIL_HOSTNAME"
echo "  Mailcow IP: $MAILCOW_IP"
echo "  Nginx Proxy: 192.168.0.9"
echo "  SSL Certificate: /etc/letsencrypt/live/$MAIL_HOSTNAME/"
echo ""
print_msg "Mail ports now being proxied:"
echo "  HTTP/HTTPS: 80, 443 → $MAILCOW_IP:8080"
echo "  SMTP: 25, 587, 465 → $MAILCOW_IP:25, 587, 465"
echo "  IMAP: 143, 993 → $MAILCOW_IP:143, 993"
echo "  POP3: 110, 995 → $MAILCOW_IP:110, 995"
echo "  Sieve: 4190 → $MAILCOW_IP:4190"
echo ""
print_msg "Next steps:"
echo "  1. Make sure Mailcow is installed and running on $MAILCOW_IP"
echo "  2. Ensure router forwards mail ports to 192.168.0.9"
echo "  3. Access Mailcow at: https://$MAIL_HOSTNAME"
echo "  4. Configure DNS records (MX, SPF, DKIM, DMARC)"
echo ""
print_msg "Configuration files:"
echo "  HTTP/HTTPS: /etc/nginx/sites-available/mailcow"
echo "  Stream: /etc/nginx/nginx.conf (stream block)"
echo "  Backup: /etc/nginx/nginx.conf.mailcow-backup"
echo ""
