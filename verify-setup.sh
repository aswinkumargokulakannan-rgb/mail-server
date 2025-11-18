#!/bin/bash

#############################################
# Mailcow + Nginx Setup Verification Script
# Run this script to verify your setup
#############################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_failure() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Ask for domain
read -p "Enter your mail server hostname (e.g., mail.example.com): " MAIL_HOSTNAME
read -p "Enter your base domain (e.g., example.com): " BASE_DOMAIN

print_header "DNS Records Check"

# Check A record
print_info "Checking A record for $MAIL_HOSTNAME..."
if host $MAIL_HOSTNAME > /dev/null 2>&1; then
    IP=$(host $MAIL_HOSTNAME | grep "has address" | awk '{print $4}' | head -1)
    print_success "A record found: $MAIL_HOSTNAME -> $IP"
else
    print_failure "A record not found for $MAIL_HOSTNAME"
fi

# Check MX record
print_info "Checking MX record for $BASE_DOMAIN..."
if host -t MX $BASE_DOMAIN > /dev/null 2>&1; then
    MX=$(host -t MX $BASE_DOMAIN | head -1)
    print_success "MX record found: $MX"
else
    print_failure "MX record not found for $BASE_DOMAIN"
fi

# Check autodiscover
print_info "Checking autodiscover record..."
if host autodiscover.$BASE_DOMAIN > /dev/null 2>&1; then
    print_success "autodiscover.$BASE_DOMAIN resolves"
else
    print_warning "autodiscover.$BASE_DOMAIN not found (optional)"
fi

# Check autoconfig
print_info "Checking autoconfig record..."
if host autoconfig.$BASE_DOMAIN > /dev/null 2>&1; then
    print_success "autoconfig.$BASE_DOMAIN resolves"
else
    print_warning "autoconfig.$BASE_DOMAIN not found (optional)"
fi

# Check SPF record
print_info "Checking SPF record..."
if host -t TXT $BASE_DOMAIN | grep -q "v=spf1"; then
    SPF=$(host -t TXT $BASE_DOMAIN | grep "v=spf1")
    print_success "SPF record found"
else
    print_warning "SPF record not found (should be added)"
fi

print_header "Port Connectivity Check"

# Check if ports are open
check_port() {
    local port=$1
    local service=$2

    if timeout 3 bash -c "echo > /dev/tcp/$MAIL_HOSTNAME/$port" 2>/dev/null; then
        print_success "Port $port ($service) is open"
        return 0
    else
        print_failure "Port $port ($service) is closed or filtered"
        return 1
    fi
}

print_info "Testing mail server ports..."
check_port 25 "SMTP"
check_port 587 "SMTP Submission"
check_port 465 "SMTPS"
check_port 143 "IMAP"
check_port 993 "IMAPS"
check_port 110 "POP3"
check_port 995 "POP3S"
check_port 80 "HTTP"
check_port 443 "HTTPS"

print_header "SSL Certificate Check"

print_info "Checking SSL certificate..."
if command -v openssl &> /dev/null; then
    SSL_INFO=$(echo | openssl s_client -servername $MAIL_HOSTNAME -connect $MAIL_HOSTNAME:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)

    if [ $? -eq 0 ]; then
        print_success "SSL certificate is valid"
        echo "$SSL_INFO" | while read line; do
            print_info "  $line"
        done
    else
        print_failure "Could not retrieve SSL certificate"
    fi
else
    print_warning "OpenSSL not installed, skipping SSL check"
fi

print_header "Web Interface Check"

print_info "Checking web interface accessibility..."
if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://$MAIL_HOSTNAME)

    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 301 ] || [ "$HTTP_CODE" -eq 302 ]; then
        print_success "Web interface is accessible (HTTP $HTTP_CODE)"
    else
        print_failure "Web interface returned HTTP $HTTP_CODE"
    fi
else
    print_warning "curl not installed, skipping web check"
fi

print_header "SMTP Connection Check"

print_info "Testing SMTP connection..."
if command -v telnet &> /dev/null || command -v nc &> /dev/null; then
    if timeout 5 bash -c "echo QUIT | nc -w 3 $MAIL_HOSTNAME 25" > /dev/null 2>&1; then
        print_success "SMTP server responds on port 25"
    elif timeout 5 bash -c "echo QUIT | telnet $MAIL_HOSTNAME 25" > /dev/null 2>&1; then
        print_success "SMTP server responds on port 25"
    else
        print_failure "SMTP server does not respond on port 25"
    fi
else
    print_warning "telnet/nc not installed, skipping SMTP connection test"
fi

print_header "Recommended Next Steps"

echo ""
print_info "1. Access Mailcow web UI: https://$MAIL_HOSTNAME"
print_info "2. Login with admin/moohoo and CHANGE PASSWORD"
print_info "3. Add your domain in Configuration → Mail setup → Domains"
print_info "4. Generate DKIM key and add to DNS"
print_info "5. Create mailboxes in Configuration → Mail setup → Mailboxes"
print_info "6. Send test email and check with https://www.mail-tester.com"
print_info "7. Add DMARC record to DNS"
print_info "8. Configure Rspamd and spam settings"
echo ""

print_header "Mail Testing Resources"

echo ""
print_info "Test your mail server configuration:"
print_info "  • Mail Tester: https://www.mail-tester.com/"
print_info "  • MX Toolbox: https://mxtoolbox.com/SuperTool.aspx?action=mx:$BASE_DOMAIN"
print_info "  • DKIM Check: https://mxtoolbox.com/dkim.aspx"
print_info "  • SPF Check: https://mxtoolbox.com/spf.aspx"
print_info "  • DMARC Check: https://mxtoolbox.com/DMARC.aspx"
echo ""

print_header "Verification Complete"
