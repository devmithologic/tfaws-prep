# n8n on AWS with Custom Domain and SSL

Documentation of the n8n deployment process on an AWS EC2 instance with a custom domain, Nginx as a reverse proxy, and a free SSL certificate via Let's Encrypt.

**Date:** February 19, 2026
**Domain:** `n8n.<YOUR_DOMAIN>.com`
**Stack:** EC2 t3.small + Docker + Nginx + Certbot + Route 53

---

## Architecture

```
Internet
    │
    ▼
Route 53 (DNS)
n8n.<YOUR_DOMAIN>.com → <YOUR_ELASTIC_IP>
    │
    ▼
EC2 t3.small (Amazon Linux)
Elastic IP: <YOUR_ELASTIC_IP>
    │
    ▼
Nginx (Reverse Proxy)
Port 80  → redirect to 443
Port 443 → SSL (Let's Encrypt)
    │
    ▼
Docker Container (n8n)
Port 5678
```

---

## Prerequisites

- AWS account with access to EC2, Route 53, and VPC
- Domain registered at Namecheap (or any registrar)
- AWS CLI configured on local machine
- SSH key pair for EC2 access

---

## Step 1: AWS Infrastructure

### 1.1 EC2 Instance

| Parameter | Value |
|-----------|-------|
| Type | t3.small |
| OS | Amazon Linux 2023 |
| Storage | 20 GB gp3 |

### 1.2 Security Group (n8n-sg)

**Inbound rules:**

| Type | Port | Source | Purpose |
|------|------|--------|---------|
| SSH | 22 | 0.0.0.0/0 | Administrative access |
| HTTP | 80 | 0.0.0.0/0 | Required for Let's Encrypt SSL validation |
| HTTPS | 443 | 0.0.0.0/0 | Secure web traffic |
| Custom TCP | 5678 | 0.0.0.0/0 | n8n native port |

**Outbound rules:**

| Type | Port | Destination |
|------|------|-------------|
| All traffic | All | 0.0.0.0/0 |

> **Security note:** For better production security, consider restricting port 443 to your personal IP once the SSL certificate is obtained. Port 80 must remain open to the internet for Certbot automatic renewals to work.

### 1.3 Elastic IP

A static IP (Elastic IP) is assigned to the instance to ensure DNS always points to the same address regardless of instance restarts.

> **Cost:** Elastic IP is free while associated with a running instance. Charges apply only when unassociated.

---

## Step 2: DNS Configuration with Route 53

### 2.1 Create Hosted Zone

AWS Console → Route 53 → Hosted Zones → Create hosted zone:

- **Domain name:** `<YOUR_DOMAIN>.com`
- **Type:** Public hosted zone

Route 53 automatically generates 4 nameservers (NS records), for example:

```
ns-XXX.awsdns-XX.com
ns-XXXX.awsdns-XX.org
ns-XXXX.awsdns-XX.co.uk
ns-XXX.awsdns-XX.net
```

### 2.2 Delegate DNS at Namecheap

Namecheap → Domain List → Manage → **Nameservers** tab:

1. Switch from "Namecheap BasicDNS" to **Custom DNS**
2. Paste the 4 Route 53 nameservers
3. Save changes

Propagation can take anywhere from 15 minutes to 48 hours.

**Verify propagation:**

```bash
# From local machine, using Google's DNS
nslookup -type=NS <YOUR_DOMAIN>.com 8.8.8.8
```

The response should show AWS nameservers (`awsdns`).

### 2.3 Create A Record for n8n

Inside the `<YOUR_DOMAIN>.com` Hosted Zone → Create record:

| Field | Value |
|-------|-------|
| Record name | `n8n` |
| Type | A |
| Value | `<YOUR_ELASTIC_IP>` |
| TTL | 300 |

**Verify:**

```bash
nslookup n8n.<YOUR_DOMAIN>.com 8.8.8.8
# Should return your instance's Elastic IP
```

---

## Step 3: Server Configuration

### 3.1 Connect to EC2

```bash
ssh -i your-key.pem ec2-user@<YOUR_ELASTIC_IP>
```

### 3.2 Install and Configure Nginx

```bash
sudo yum update -y
sudo yum install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
```

Create a basic config for Certbot validation:

```bash
sudo nano /etc/nginx/conf.d/n8n.conf
```

```nginx
server {
    listen 80;
    server_name n8n.<YOUR_DOMAIN>.com;

    location / {
        return 200 'ok';
    }
}
```

```bash
sudo nginx -t
sudo systemctl reload nginx
```

**Verify from local machine:**

```bash
curl -I http://n8n.<YOUR_DOMAIN>.com
# Should respond with HTTP/1.1 200 OK
```

---

## Step 4: SSL Certificate with Let's Encrypt

### 4.1 Install Certbot

```bash
sudo yum install python3-certbot-nginx -y
```

### 4.2 Obtain Certificate

```bash
sudo certbot --nginx -d n8n.<YOUR_DOMAIN>.com
```

Certbot performs an HTTP challenge: it accesses `http://n8n.<YOUR_DOMAIN>.com/.well-known/acme-challenge/` to verify domain ownership. This is why port 80 must be open to the internet at this point.

On success, certificates are saved at:

```
/etc/letsencrypt/live/n8n.<YOUR_DOMAIN>.com/fullchain.pem
/etc/letsencrypt/live/n8n.<YOUR_DOMAIN>.com/privkey.pem
```

### 4.3 Automatic Renewal

Let's Encrypt certificates expire every **90 days**. Certbot automatically installs a systemd timer that checks and renews certificates twice a day, acting only when less than 30 days remain before expiration.

**Verify the timer is active:**

```bash
sudo systemctl status certbot-renew.timer
```

**Simulate a renewal (dry run):**

```bash
sudo certbot renew --dry-run
```

No manual action is required for renewals.

---

## Step 5: Nginx as Reverse Proxy

Replace the contents of `/etc/nginx/conf.d/n8n.conf`:

```bash
sudo nano /etc/nginx/conf.d/n8n.conf
```

```nginx
server {
    listen 80;
    server_name n8n.<YOUR_DOMAIN>.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name n8n.<YOUR_DOMAIN>.com;

    ssl_certificate /etc/letsencrypt/live/n8n.<YOUR_DOMAIN>.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/n8n.<YOUR_DOMAIN>.com/privkey.pem;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
sudo nginx -t
sudo systemctl reload nginx
```

**What this configuration does:**

- The port 80 block redirects all HTTP traffic to HTTPS (301 redirect)
- The port 443 block handles HTTPS traffic using the SSL certificates
- `proxy_pass` forwards requests to the n8n container on port 5678
- Proxy headers allow n8n to know the real client IP and support WebSockets

---

## Step 6: n8n Configuration

### 6.1 Project Structure

```
n8n-deployment/
├── docker-compose.yml
├── .env               ← never commit this file
└── .env.example       ← commit this instead
```

### 6.2 docker-compose.yml

```yaml
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - GENERIC_TIMEZONE=${TIMEZONE}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=sqlite
      - DB_SQLITE_DATABASE=/home/node/.n8n/database.sqlite
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n-network

volumes:
  n8n_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
```

### 6.3 .env.example

Commit this file as a reference template. Copy it to `.env` and fill in your actual values:

```env
N8N_HOST=n8n.<YOUR_DOMAIN>.com
N8N_PROTOCOL=https
WEBHOOK_URL=https://n8n.<YOUR_DOMAIN>.com/
TIMEZONE=America/Mexico_City
N8N_ENCRYPTION_KEY=<securely-generated-key>
```

### 6.4 Start n8n

```bash
cd ~/n8n-deployment
docker-compose down
docker-compose up -d
docker-compose logs -f n8n
```

n8n should show in the logs:

```
Editor is now accessible via:
https://n8n.<YOUR_DOMAIN>.com
```

---

## Final Verification

Open `https://n8n.<YOUR_DOMAIN>.com` in your browser. You should see:

- Green padlock (SSL active)
- n8n interface loading correctly

---

## Errors Encountered and Solutions

### Error: NXDOMAIN on Certbot

```
DNS problem: NXDOMAIN looking up A for n8n.<YOUR_DOMAIN>.com
```

**Cause:** Namecheap nameservers had not yet been replaced by Route 53's, or the A record in Route 53 had the wrong IP.

**Solution:** Verify DNS propagation with `nslookup -type=NS <YOUR_DOMAIN>.com 8.8.8.8` and confirm the A record points to the correct Elastic IP.

### Error: Timeout on Certbot

```
Timeout during connect (likely firewall problem)
```

**Cause:** The A record in Route 53 had a typo in the IP address.

**Solution:** Fix the A record in Route 53 with the exact Elastic IP and wait for TTL propagation (300 seconds).

**Lesson learned:** Always verify the full Elastic IP from the AWS console before creating the DNS record. A single missing digit can cost hours of debugging.

---

## Next Steps

- [ ] Migrate infrastructure to Terraform (IaC) using `terraform import`
- [ ] Configure automatic backups for the n8n data volume
- [ ] Restrict Security Group access by IP
- [ ] Set up monitoring with CloudWatch

---

## Resources

- [n8n official hosting docs](https://docs.n8n.io/hosting/)
- [Certbot for Nginx](https://certbot.eff.org/instructions?os=centosrhel8&webserver=nginx)
- [Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/)