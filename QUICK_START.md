# Mailcow Quick Start Guide (Existing Nginx Proxy)

This guide is for setting up Mailcow when you **already have an Nginx proxy server running** (like at 192.168.0.9).

## Architecture

```
Internet
    |
    v
[Router] - Ports forwarded to your existing Nginx (192.168.0.9)
    |
    v
[Your Existing Nginx Server - 192.168.0.9]
    |
    v
[Mailcow VM] - New mail server
```

## What You Need

- **Existing Nginx Server**: Already running at 192.168.0.9
- **New Mailcow VM**: 6GB RAM minimum, 20GB+ disk (Ubuntu/Debian)
- Domain name with DNS control
- Router already forwarding web traffic to 192.168.0.9

## Step-by-Step Setup

### Step 1: Prepare DNS Records

Add these DNS records (replace `example.com` with your domain):

```
Type    Name                        Value               TTL
A       mail.example.com            YOUR_PUBLIC_IP      3600
MX      example.com                 mail.example.com    3600
A       autodiscover.example.com    YOUR_PUBLIC_IP      3600
A       autoconfig.example.com      YOUR_PUBLIC_IP      3600
TXT     example.com                 "v=spf1 mx ~all"    3600
```

### Step 2: Install Mailcow on Your Mail Server VM

SSH into your new mail server VM and run:

```bash
# Download the installation script
wget https://raw.githubusercontent.com/aswinkumargokulakannan-rgb/mail-server/main/install-mailcow.sh

# Make it executable
chmod +x install-mailcow.sh

# Run the installation
sudo ./install-mailcow.sh
```

Follow the prompts:
- Enter your mail server hostname: `mail.example.com`
- Enter your timezone: e.g., `America/New_York` or `Asia/Kolkata`
- Choose to start Mailcow when prompted

**Important**: Note down your Mailcow VM's IP address. You can find it with:
```bash
ip addr show | grep "inet "
```

Example output: `192.168.0.50` (your IP may differ)

### Step 3: Add Mailcow Configuration to Your Existing Nginx

SSH into your **existing Nginx server (192.168.0.9)** and run:

```bash
# Download the configuration script
wget https://raw.githubusercontent.com/aswinkumargokulakannan-rgb/mail-server/main/add-mailcow-to-nginx.sh

# Make it executable
chmod +x add-mailcow-to-nginx.sh

# Run the script
sudo ./add-mailcow-to-nginx.sh
```

Follow the prompts:
- Enter Mailcow VM IP: `192.168.0.50` (or whatever you noted in Step 2)
- Enter mail hostname: `mail.example.com`
- Enter base domain: `example.com`

The script will:
- Generate SSL certificates with Let's Encrypt
- Add HTTP/HTTPS reverse proxy configuration
- Add TCP stream proxy for mail protocols (SMTP, IMAP, POP3)
- Test and reload Nginx

### Step 4: Configure Router Port Forwarding

Make sure your router forwards these ports to your **Nginx server (192.168.0.9)**:

| Port | Service | Already Forwarded? |
|------|---------|-------------------|
| 80   | HTTP    | ✓ Probably yes |
| 443  | HTTPS   | ✓ Probably yes |
| 25   | SMTP    | ⚠️ Add this |
| 587  | SMTP Submission | ⚠️ Add this |
| 465  | SMTPS   | ⚠️ Add this |
| 143  | IMAP    | ⚠️ Add this |
| 993  | IMAPS   | ⚠️ Add this |
| 110  | POP3    | ⚠️ Add this |
| 995  | POP3S   | ⚠️ Add this |
| 4190 | Sieve   | ⚠️ Add this |

You likely already have 80 and 443 forwarded. Just add the mail-specific ports.

### Step 5: Access and Configure Mailcow

1. Open your browser and go to: `https://mail.example.com`

2. Login with default credentials:
   - **Username**: `admin`
   - **Password**: `moohoo`

3. **IMMEDIATELY CHANGE THE PASSWORD!**
   - Click on "Admin" in top right
   - Go to "Edit admin details"
   - Change password

4. Add your domain:
   - Go to **Configuration → Mail setup → Domains**
   - Click "Add domain"
   - Enter your domain: `example.com`

5. Generate DKIM key:
   - Go to **Configuration → Configuration & Details → ARC/DKIM keys**
   - Select your domain
   - Click "Generate" if not already generated
   - Copy the DKIM DNS record
   - Add it to your DNS

6. Create email accounts:
   - Go to **Configuration → Mail setup → Mailboxes**
   - Click "Add mailbox"
   - Enter email address: e.g., `admin@example.com`
   - Set password and quota

### Step 6: Add Additional DNS Records

After setting up DKIM, add the DMARC record:

```
Type    Name                    Value
TXT     _dmarc.example.com      "v=DMARC1; p=quarantine; rua=mailto:admin@example.com"
```

### Step 7: Test Your Setup

Run the verification script:

```bash
wget https://raw.githubusercontent.com/aswinkumargokulakannan-rgb/mail-server/main/verify-setup.sh
chmod +x verify-setup.sh
./verify-setup.sh
```

Also test with:
- **Mail Tester**: https://www.mail-tester.com/ (aim for 10/10 score)
- **MX Toolbox**: https://mxtoolbox.com/
- Send test emails to Gmail, Outlook, etc.

## Network Diagram

```
┌─────────────────────────────────────────────┐
│ Internet                                     │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│ Router                                       │
│ Port Forwarding:                            │
│  80, 443, 25, 587, 465, 143, 993, 110, 995  │
│         ↓                                    │
│    192.168.0.9                              │
└────────────────┬────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────┐
│ Nginx Proxy Server - 192.168.0.9           │
│                                              │
│ HTTP/HTTPS (80/443) ─────────┐             │
│ Mail Protocols (25, 587...) ─┤             │
│ Your other services ─────────┤             │
└─────────────┬────────────────┴──────────────┘
              │
              ├──────────────┐
              │              │
              ▼              ▼
      ┌──────────────┐ ┌──────────────┐
      │ Mailcow VM   │ │ Other VMs    │
      │ (Mail Server)│ │ (Web, etc.)  │
      │ :8080, :25...│ │              │
      └──────────────┘ └──────────────┘
```

## Firewall Configuration

### On Mailcow VM

The Mailcow VM doesn't need to accept external connections. All traffic comes through Nginx:

```bash
# Allow from Nginx server only
sudo ufw allow from 192.168.0.9
sudo ufw enable
```

### On Nginx Server (192.168.0.9)

Make sure these ports are open:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 25/tcp
sudo ufw allow 587/tcp
sudo ufw allow 465/tcp
sudo ufw allow 143/tcp
sudo ufw allow 993/tcp
sudo ufw allow 110/tcp
sudo ufw allow 995/tcp
sudo ufw allow 4190/tcp
sudo ufw enable
```

## What This Setup Does

1. **Web UI (HTTPS)**: Nginx receives requests on port 443 and forwards to Mailcow's port 8080
2. **Mail Protocols**: Nginx uses TCP stream proxying to forward mail traffic directly to Mailcow
3. **SSL**: Let's Encrypt handles web UI SSL, Mailcow handles mail protocol SSL/TLS
4. **Autodiscover/Autoconfig**: Nginx proxies these for automatic email client configuration

## Troubleshooting

### Can't access web interface

```bash
# On Nginx server, check if configuration is working
sudo nginx -t
sudo systemctl status nginx

# Check if you can reach Mailcow from Nginx server
curl http://MAILCOW_IP:8080

# Check Nginx logs
sudo tail -f /var/log/nginx/mailcow-error.log
```

### Can't send/receive emails

```bash
# On Nginx server, verify mail ports are listening
sudo netstat -tulpn | grep -E ':(25|587|465|143|993)'

# Test connection to Mailcow from Nginx server
telnet MAILCOW_IP 25

# Check stream logs
sudo tail -f /var/log/nginx/mail-stream-access.log
```

### SSL certificate issues

```bash
# Check certificates
sudo certbot certificates

# Renew manually if needed
sudo certbot renew
sudo systemctl reload nginx
```

## Management Commands

### Mailcow Management (on Mailcow VM)

```bash
cd /opt/mailcow-dockerized

# View status
docker-compose ps

# View logs
docker-compose logs -f

# Restart
docker-compose restart

# Update
./update.sh

# Backup
./helper-scripts/backup_and_restore.sh backup all
```

### Nginx Management (on Nginx server)

```bash
# Test configuration
sudo nginx -t

# Reload configuration
sudo systemctl reload nginx

# Restart Nginx
sudo systemctl restart nginx

# View mailcow access logs
sudo tail -f /var/log/nginx/mailcow-access.log

# View mail protocol logs
sudo tail -f /var/log/nginx/mail-stream-access.log
```

## Files Created

On your Nginx server (192.168.0.9):
- `/etc/nginx/sites-available/mailcow` - HTTP/HTTPS configuration
- `/etc/nginx/nginx.conf` - Stream configuration added
- `/etc/letsencrypt/live/mail.example.com/` - SSL certificates

On your Mailcow VM:
- `/opt/mailcow-dockerized/` - Mailcow installation
- `/opt/mailcow-dockerized/mailcow.conf` - Main configuration

## Daily Operations

### Adding Email Accounts

1. Login to https://mail.example.com
2. Go to **Configuration → Mail setup → Mailboxes**
3. Click **Add mailbox**

### Checking Mail Logs

```bash
# On Mailcow VM
cd /opt/mailcow-dockerized
docker-compose logs -f postfix-mailcow
docker-compose logs -f dovecot-mailcow
```

### Monitoring Spam

1. Login to https://mail.example.com
2. Go to **System → Logs → Rspamd History**

## Security Checklist

- ✅ Changed default admin password
- ✅ Generated DKIM key and added to DNS
- ✅ Added SPF record
- ✅ Added DMARC record
- ✅ Enabled fail2ban (included in Mailcow)
- ✅ Regular backups configured
- ✅ Firewall configured on both VMs
- ✅ SSL certificates auto-renewing
- ✅ Only necessary ports exposed

## Need Help?

- **Mailcow Docs**: https://docs.mailcow.email/
- **Check mail score**: https://www.mail-tester.com/
- **DNS tools**: https://mxtoolbox.com/

## Summary

You now have:
- Mailcow running on a dedicated VM
- All mail services proxied through your existing Nginx server
- Single point of entry (192.168.0.9) for all services
- Minimal router configuration changes
- Professional mail server with webmail, spam filtering, and more!
