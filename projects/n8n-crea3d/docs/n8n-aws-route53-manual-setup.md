# n8n on AWS with Route 53 Domain - Manual Setup Guide

Complete step-by-step guide to deploy n8n on AWS EC2 with a custom domain using Route 53, SSL/HTTPS, and automated backups.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Phase 1: Elastic IP Setup](#phase-1-elastic-ip-setup)
4. [Phase 2: Domain Registration](#phase-2-domain-registration)
5. [Phase 3: EC2 Instance Setup](#phase-3-ec2-instance-setup)
6. [Phase 4: DNS Configuration](#phase-4-dns-configuration)
7. [Phase 5: n8n Deployment](#phase-5-n8n-deployment)
8. [Phase 6: SSL/HTTPS Setup](#phase-6-sslhttps-setup)
9. [Phase 7: Backups & Monitoring](#phase-7-backups--monitoring)
10. [Cost Breakdown](#cost-breakdown)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required
- AWS Account with billing enabled
- AWS CLI installed and configured ([Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html))
- SSH key pair in AWS
- Credit card for domain registration (~$13-40/year depending on TLD)
- Basic Linux command line knowledge

### Recommended
- Domain name ideas prepared (2-3 options in case first choice is taken)
- Email address you check regularly (for domain verification)

### Verify AWS CLI Setup
```bash
aws --version
# Should show: aws-cli/2.x.x

aws sts get-caller-identity
# Should return your AWS account details
```

---

## Architecture Overview

```
Internet → Route 53 DNS → Elastic IP → EC2 Instance
                                          ├── Docker
                                          ├── n8n (port 5678)
                                          ├── Nginx (reverse proxy)
                                          └── PostgreSQL (optional)
                                          
Backups → S3 Bucket
```

**Components:**
- **Route 53**: DNS management + domain registration
- **Elastic IP**: Permanent public IP address (free while EC2 is running)
- **EC2 t3.small**: Application server (Amazon Linux 2023)
- **Docker & Docker Compose**: Container runtime
- **n8n**: Workflow automation platform
- **Nginx**: Reverse proxy with SSL termination
- **Let's Encrypt**: Free SSL certificates
- **S3**: Backup storage (optional)

---

## Phase 1: Elastic IP Setup

**Why?** EC2 instances get a new IP every time they stop/start. Elastic IP provides a permanent address.

### Step 1.1: Allocate Elastic IP

**AWS Console Method:**
1. Go to [EC2 Dashboard](https://console.aws.amazon.com/ec2/)
2. Left menu → **Elastic IPs**
3. Click **Allocate Elastic IP address**
4. Settings:
   - Network Border Group: Default
   - Public IPv4 address pool: Amazon's pool
5. Click **Allocate**
6. **Note the allocated IP** (e.g., 52.45.123.89)

**AWS CLI Method:**
```bash
# Allocate Elastic IP
aws ec2 allocate-address --domain vpc

# Output:
# {
#     "PublicIp": "52.45.123.89",
#     "AllocationId": "eipalloc-xxxxx",
#     "Domain": "vpc"
# }

# Save these values
export EIP_ALLOCATION_ID="eipalloc-xxxxx"
export ELASTIC_IP="52.45.123.89"
```

### Step 1.2: Create EC2 Instance

**AWS Console Method:**
1. EC2 Dashboard → **Launch Instance**
2. Configure:
   - **Name**: `n8n-production`
   - **AMI**: Amazon Linux 2023
   - **Instance type**: `t3.small` (2 vCPU, 2GB RAM)
   - **Key pair**: Select existing or create new
   - **Network settings**:
     - VPC: Default
     - Auto-assign public IP: Enable (temporary, will replace with Elastic IP)
   - **Configure storage**: 20 GB gp3
   - **Advanced details** → User data: Leave empty for now
3. Click **Launch instance**
4. Wait for instance state: **Running**
5. **Note the Instance ID** (e.g., i-0123456789abcdef)

**AWS CLI Method:**
```bash
# Get Amazon Linux 2023 AMI ID for your region
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*" "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

echo "AMI ID: $AMI_ID"

# Create Security Group
SG_ID=$(aws ec2 create-security-group \
  --group-name n8n-security-group \
  --description "Security group for n8n instance" \
  --query 'GroupId' \
  --output text)

echo "Security Group: $SG_ID"

# Add inbound rules
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 \
  --group-name n8n-security-group

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.small \
  --key-name your-key-pair-name \
  --security-group-ids $SG_ID \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=n8n-production}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
echo "Instance is now running"
```

### Step 1.3: Associate Elastic IP to Instance

**AWS Console Method:**
1. EC2 → **Elastic IPs**
2. Select your Elastic IP
3. **Actions** → **Associate Elastic IP address**
4. Settings:
   - Resource type: Instance
   - Instance: Select your n8n instance
   - Private IP: Leave default
5. Click **Associate**

**AWS CLI Method:**
```bash
# Associate Elastic IP to instance
aws ec2 associate-address \
  --instance-id $INSTANCE_ID \
  --allocation-id $EIP_ALLOCATION_ID

echo "✓ Elastic IP $ELASTIC_IP associated to instance $INSTANCE_ID"
```

### Step 1.4: Verify Connection

```bash
# SSH to instance using Elastic IP
ssh -i your-key.pem ec2-user@$ELASTIC_IP

# If successful, you should see Amazon Linux prompt
# Exit for now
exit
```

**✅ Phase 1 Complete:** You now have an EC2 instance with a permanent IP address.

---

## Phase 2: Domain Registration

### Step 2.1: Choose Domain Name

**Recommendations:**
- Keep it short and memorable
- Avoid hyphens and numbers if possible
- Choose appropriate TLD for your use case

**Common TLDs and Costs:**
| TLD | Annual Cost | Best For |
|-----|-------------|----------|
| .com | $13 | Professional businesses |
| .tech | $18 | Technology/automation |
| .io | $32 | Tech startups |
| .click | $3 | Budget-friendly |

### Step 2.2: Register Domain in Route 53

**AWS Console Method:**
1. Go to [Route 53 Console](https://console.aws.amazon.com/route53/)
2. Left menu → **Registered domains**
3. Click **Register domain**
4. Search for your desired domain (e.g., `yourcompany.com`)
5. AWS shows availability and pricing
6. If available, click **Add to cart** → **Continue**
7. **Domain details:**
   - Duration: 1 year (minimum)
   - Auto-renew: **Enable** ✅ (important!)
8. **Contact information:**
   - Fill all required fields
   - **Email**: Use an address you check regularly ⚠️
   - Privacy protection: **Enable** (recommended)
9. Review and accept terms
10. Click **Complete order**
11. **Cost will be charged immediately**

**AWS CLI Method:**
```bash
# Check domain availability
aws route53domains check-domain-availability \
  --domain-name yourcompany.com \
  --region us-east-1

# Output shows: "Availability": "AVAILABLE" or "UNAVAILABLE"

# Note: Registration via CLI is complex
# Recommend using Console for first-time registration
```

### Step 2.3: Verify Email (CRITICAL)

⚠️ **Do this within 24 hours or your domain will be suspended!**

1. **Check your email** (including spam folder)
2. **From**: `no-reply-aws@amazon.com`
3. **Subject**: "Please verify the email address for your domain..."
4. **Click the verification link**
5. You should see: "Email address verified successfully"

**Verify in Console:**
```
Route 53 → Registered domains → yourcompany.com
Status should show: "Verification status: Verified"
```

**⏱️ Domain Activation:** Usually 10-30 minutes, can take up to 48 hours.

### Step 2.4: Verify Hosted Zone Creation

Route 53 automatically creates a Hosted Zone for your domain.

**Check in Console:**
```
Route 53 → Hosted zones
You should see: yourcompany.com
```

**Check via CLI:**
```bash
# List hosted zones
aws route53 list-hosted-zones \
  --query 'HostedZones[*].[Name,Id]' \
  --output table

# Get Hosted Zone ID for your domain
ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='yourcompany.com.'].Id" \
  --output text | cut -d'/' -f3)

echo "Hosted Zone ID: $ZONE_ID"
```

**✅ Phase 2 Complete:** You own a domain and it's verified.

---

## Phase 3: EC2 Instance Setup

### Step 3.1: Connect to Instance

```bash
# SSH to your instance
ssh -i your-key.pem ec2-user@$ELASTIC_IP
```

### Step 3.2: Update System and Install Dependencies

```bash
# Update system packages
sudo yum update -y

# Install Docker
sudo yum install -y docker

# Start and enable Docker
sudo systemctl enable docker
sudo systemctl start docker

# Add ec2-user to docker group (to run docker without sudo)
sudo usermod -aG docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installations
docker --version
docker-compose --version

# Install Nginx
sudo yum install -y nginx

# Install Python pip (for Certbot)
sudo yum install -y python3-pip

# Install Certbot for SSL certificates
sudo pip3 install certbot certbot-nginx

# Verify Certbot
certbot --version
```

### Step 3.3: Logout and Reconnect

```bash
# Exit current session
exit

# Reconnect to apply docker group changes
ssh -i your-key.pem ec2-user@$ELASTIC_IP

# Verify docker works without sudo
docker ps
# Should show: CONTAINER ID   IMAGE   (empty list is ok)
```

**✅ Phase 3 Complete:** EC2 instance is ready with all dependencies.

---

## Phase 4: DNS Configuration

### Step 4.1: Create DNS Record for n8n

**Decision:** Choose subdomain structure:
- Option A: `automation.yourcompany.com` (recommended)
- Option B: `n8n.yourcompany.com`
- Option C: `yourcompany.com` (root domain)

**AWS Console Method:**
1. Route 53 → **Hosted zones** → Click your domain
2. Click **Create record**
3. Configure:
   - **Record name**: `automation` (or leave empty for root)
   - **Record type**: A
   - **Value**: Your Elastic IP (e.g., 52.45.123.89)
   - **TTL**: 300 (5 minutes)
   - **Routing policy**: Simple routing
4. Click **Create records**

**AWS CLI Method:**
```bash
# Set your domain and subdomain
DOMAIN="yourcompany.com"
SUBDOMAIN="automation"  # Change as needed
FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN}"

# Create A record
cat > /tmp/dns-record.json << EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "${FULL_DOMAIN}",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "${ELASTIC_IP}"}]
    }
  }]
}
EOF

# Apply DNS change
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch file:///tmp/dns-record.json

echo "✓ DNS record created: $FULL_DOMAIN → $ELASTIC_IP"
```

### Step 4.2: Verify DNS Propagation

```bash
# Check DNS resolution (from your local machine)
nslookup automation.yourcompany.com

# Should return your Elastic IP
# Name:    automation.yourcompany.com
# Address: 52.45.123.89

# Alternative with dig
dig automation.yourcompany.com +short
# Should output: 52.45.123.89
```

**⏱️ Propagation time:** Usually 2-10 minutes, can take up to 48 hours globally.

**✅ Phase 4 Complete:** DNS is configured and resolving.

---

## Phase 5: n8n Deployment

### Step 5.1: Create n8n Directory Structure

```bash
# On EC2 instance
mkdir -p ~/n8n-deployment
cd ~/n8n-deployment
```

### Step 5.2: Create Docker Compose Configuration

```bash
# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=${WEBHOOK_URL}
      - GENERIC_TIMEZONE=America/Mexico_City
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      
      # Database configuration (SQLite for simplicity)
      - DB_TYPE=sqlite
      - DB_SQLITE_DATABASE=/home/node/.n8n/database.sqlite
      
      # Performance settings
      - N8N_METRICS=true
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  n8n_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
EOF
```

### Step 5.3: Create Environment File

```bash
# Generate encryption key
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Create .env file
# Replace 'automation.yourcompany.com' with YOUR domain
cat > .env << EOF
WEBHOOK_URL=https://automation.yourcompany.com/
N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY
EOF

# Verify .env was created
cat .env
```

### Step 5.4: Start n8n (HTTP only, for now)

```bash
# Start n8n container
docker-compose up -d

# Check logs
docker-compose logs -f n8n

# Should see: "n8n ready on http://0.0.0.0:5678"
# Press Ctrl+C to exit logs

# Verify container is running
docker ps
# Should show n8n container
```

### Step 5.5: Test Local Access

```bash
# From EC2 instance
curl http://localhost:5678

# Should return HTML (n8n interface)
```

**✅ Phase 5 Complete:** n8n is running (HTTP only, will add HTTPS next).

---

## Phase 6: SSL/HTTPS Setup

### Step 6.1: Configure Nginx as Reverse Proxy

```bash
# Create Nginx configuration
# Replace 'automation.yourcompany.com' with YOUR domain
sudo tee /etc/nginx/conf.d/n8n.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name automation.yourcompany.com;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        
        # WebSocket support (required for n8n)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        
        # Forwarding headers
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts (for long-running workflows)
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        
        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF
```

### Step 6.2: Test and Start Nginx

```bash
# Test Nginx configuration
sudo nginx -t
# Should show: syntax is ok, test is successful

# Start Nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Verify Nginx is running
sudo systemctl status nginx
# Should show: active (running)
```

### Step 6.3: Verify HTTP Access

```bash
# From your local machine (not EC2)
curl http://automation.yourcompany.com

# Should return HTML from n8n
```

### Step 6.4: Obtain SSL Certificate

```bash
# On EC2 instance
# Replace email and domain with YOUR details
sudo certbot --nginx \
  -d automation.yourcompany.com \
  --non-interactive \
  --agree-tos \
  --email your-email@example.com \
  --redirect

# Certbot will:
# 1. Verify domain ownership
# 2. Obtain certificate from Let's Encrypt
# 3. Configure Nginx for HTTPS
# 4. Set up HTTP → HTTPS redirect

# Should see: "Successfully received certificate"
```

**If you get an error:**
- Verify DNS is resolving correctly: `nslookup automation.yourcompany.com`
- Verify port 80 is open in Security Group
- Verify Nginx is running: `sudo systemctl status nginx`

### Step 6.5: Update n8n Configuration for HTTPS

```bash
cd ~/n8n-deployment

# n8n needs to know it's behind HTTPS
# Environment variables are already set in docker-compose.yml
# Just restart n8n

docker-compose down
docker-compose up -d

# Check logs
docker-compose logs -f n8n
# Should see: "n8n ready on https://automation.yourcompany.com"
# Press Ctrl+C to exit
```

### Step 6.6: Verify HTTPS Access

Open your browser and navigate to:
```
https://automation.yourcompany.com
```

**You should see:**
- ✅ Green padlock (valid SSL certificate)
- ✅ n8n setup wizard or login screen
- ✅ No security warnings
- ✅ HTTP automatically redirects to HTTPS

### Step 6.7: Configure SSL Auto-Renewal

```bash
# Certbot automatically sets up renewal
# But let's verify and add manual cron as backup

# Test renewal (dry run)
sudo certbot renew --dry-run

# Should show: "Congratulations, all simulated renewals succeeded"

# Add cron job for automatic renewal
(crontab -l 2>/dev/null; echo "0 3 * * * sudo certbot renew --quiet --nginx") | crontab -

# Verify cron job was added
crontab -l
```

**✅ Phase 6 Complete:** n8n is accessible via HTTPS with auto-renewing SSL!

---

## Phase 7: Backups & Monitoring

### Step 7.1: Create S3 Bucket for Backups (Optional)

**AWS Console Method:**
1. Go to [S3 Console](https://s3.console.aws.amazon.com/)
2. Click **Create bucket**
3. Configure:
   - **Bucket name**: `n8n-backups-yourcompany` (must be globally unique)
   - **Region**: Same as your EC2 instance
   - **Block Public Access**: Keep all enabled
   - **Bucket Versioning**: Enable (recommended)
4. Click **Create bucket**

**AWS CLI Method:**
```bash
# Create bucket
BUCKET_NAME="n8n-backups-yourcompany-$(date +%s)"
aws s3 mb s3://$BUCKET_NAME

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Set lifecycle policy (delete backups older than 30 days)
cat > /tmp/lifecycle.json << 'EOF'
{
  "Rules": [{
    "Id": "DeleteOldBackups",
    "Status": "Enabled",
    "ExpirationInDays": 30,
    "NoncurrentVersionExpirationInDays": 7
  }]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket $BUCKET_NAME \
  --lifecycle-configuration file:///tmp/lifecycle.json

echo "Backup bucket created: $BUCKET_NAME"
```

### Step 7.2: Configure IAM Role for EC2 (for S3 access)

**AWS Console Method:**
1. IAM → **Roles** → **Create role**
2. Trusted entity: **AWS service** → **EC2**
3. Permissions: Search and add **AmazonS3FullAccess** (or create custom policy)
4. Role name: `n8n-ec2-s3-backup-role`
5. **Create role**
6. **Attach role to EC2:**
   - EC2 → Instances → Select your instance
   - Actions → Security → Modify IAM role
   - Select: `n8n-ec2-s3-backup-role`
   - **Update IAM role**

### Step 7.3: Create Backup Script

```bash
# On EC2 instance
cd ~/n8n-deployment

cat > backup.sh << 'EOF'
#!/bin/bash
# n8n Backup Script

BACKUP_DIR="/home/ec2-user/n8n-backups"
DATE=$(date +%Y%m%d_%H%M%S)
S3_BUCKET="n8n-backups-yourcompany"  # Replace with your bucket name

mkdir -p $BACKUP_DIR

echo "Starting backup at $(date)"

# Backup Docker volumes
docker run --rm \
  -v n8n_data:/data \
  -v $BACKUP_DIR:/backup \
  amazonlinux:2023 tar czf /backup/n8n-data-$DATE.tar.gz /data

# Upload to S3
aws s3 cp $BACKUP_DIR/n8n-data-$DATE.tar.gz s3://$S3_BUCKET/

# Remove local backups older than 3 days
find $BACKUP_DIR -type f -mtime +3 -delete

echo "Backup completed at $(date)"
EOF

# Make executable
chmod +x backup.sh

# Test backup
./backup.sh

# Verify backup in S3
aws s3 ls s3://n8n-backups-yourcompany/
```

### Step 7.4: Schedule Automated Backups

```bash
# Add daily backup at 2 AM
(crontab -l 2>/dev/null; echo "0 2 * * * /home/ec2-user/n8n-deployment/backup.sh >> /var/log/n8n-backup.log 2>&1") | crontab -

# Verify cron job
crontab -l
```

### Step 7.5: Create Health Check Script

```bash
cat > ~/healthcheck.sh << 'EOF'
#!/bin/bash
# n8n Health Check Script

if ! curl -f http://localhost:5678/healthz > /dev/null 2>&1; then
    echo "n8n health check failed at $(date)" >> /var/log/n8n-healthcheck.log
    
    # Restart n8n
    cd /home/ec2-user/n8n-deployment
    docker-compose restart
    
    # Optional: Send alert (configure SNS topic)
    # aws sns publish --topic-arn arn:aws:sns:region:account:topic --message "n8n is down"
fi
EOF

chmod +x ~/healthcheck.sh

# Run health check every 5 minutes
(crontab -l 2>/dev/null; echo "*/5 * * * * /home/ec2-user/healthcheck.sh") | crontab -
```

### Step 7.6: Create System Monitoring Script

```bash
cat > ~/monitor.sh << 'EOF'
#!/bin/bash
# System Status Monitor

echo "=== n8n System Status ==="
echo "Date: $(date)"
echo ""

echo "Disk Usage:"
df -h | grep -v tmpfs

echo ""
echo "Memory Usage:"
free -h

echo ""
echo "Docker Containers:"
docker ps

echo ""
echo "n8n Logs (last 10 lines):"
docker logs n8n --tail 10

echo ""
echo "Nginx Status:"
systemctl status nginx | head -3
EOF

chmod +x ~/monitor.sh

# Run it
./monitor.sh
```

**✅ Phase 7 Complete:** Backups and monitoring configured!

---

## Cost Breakdown

### Monthly Costs

| Service | Specification | Monthly Cost | Annual Cost |
|---------|--------------|--------------|-------------|
| **Domain (.com)** | Route 53 registration | $1.08 | $13 |
| **Route 53 Hosted Zone** | DNS hosting | $0.50 | $6 |
| **DNS Queries** | First 1M/month | $0 (free tier) | $0 |
| **EC2 t3.small** | 2 vCPU, 2GB RAM | ~$15 | $180 |
| **EBS gp3** | 20 GB storage | ~$2 | $24 |
| **Elastic IP** | While EC2 running | $0 | $0 |
| **Data Transfer** | First 100GB/month | $0 (free tier) | $0 |
| **S3 Backups** | ~5GB storage | ~$0.12 | ~$1.44 |
| **Total** | - | **~$18.70** | **~$224** |

### Cost Optimization Tips

1. **Use Reserved Instances**: Save up to 40% on EC2 with 1-year commitment
2. **Right-size instance**: Monitor usage, downgrade to t3.micro if sufficient
3. **Stop when not in use**: EC2 stopped = no compute charges (but Elastic IP costs $3.60/month)
4. **Use S3 Intelligent-Tiering**: Automatically moves old backups to cheaper storage
5. **Free tier**: New AWS accounts get 750 hours/month of t3.micro free for 12 months

---

## Troubleshooting

### Issue: Cannot connect to instance via SSH

**Symptoms:**
```
ssh: connect to host XX.XX.XX.XX port 22: Connection refused
```

**Solutions:**
1. Verify Security Group allows port 22:
   ```bash
   aws ec2 describe-security-groups --group-ids $SG_ID \
     --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
   ```

2. Verify instance is running:
   ```bash
   aws ec2 describe-instances --instance-ids $INSTANCE_ID \
     --query 'Reservations[0].Instances[0].State.Name'
   ```

3. Use correct username (`ec2-user` for Amazon Linux)

4. Verify key permissions:
   ```bash
   chmod 400 your-key.pem
   ```

### Issue: Domain not resolving

**Symptoms:**
```
nslookup automation.yourcompany.com
Server can't find automation.yourcompany.com: NXDOMAIN
```

**Solutions:**
1. Wait 5-10 minutes for DNS propagation

2. Verify DNS record exists:
   ```bash
   aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID \
     --query 'ResourceRecordSets[?Name==`automation.yourcompany.com.`]'
   ```

3. Check if domain was verified:
   ```
   Route 53 → Registered domains → Check verification status
   ```

### Issue: Certbot fails to obtain certificate

**Error:**
```
Failed authorization procedure. automation.yourcompany.com (http-01): 
Connection refused
```

**Solutions:**
1. Verify port 80 is open in Security Group

2. Verify Nginx is running:
   ```bash
   sudo systemctl status nginx
   ```

3. Verify DNS resolves to correct IP:
   ```bash
   nslookup automation.yourcompany.com
   ```

4. Test HTTP access:
   ```bash
   curl http://automation.yourcompany.com
   ```

### Issue: n8n shows "secure cookie" error

**Symptoms:**
Browser shows error about secure cookies when accessing via HTTP

**Solution:**
This is expected! n8n requires HTTPS. Complete Phase 6 to set up SSL.

If you must test via HTTP temporarily:
```bash
# Add to .env
echo "N8N_SECURE_COOKIE=false" >> .env

# Restart n8n
docker-compose restart
```

### Issue: n8n container keeps restarting

**Check logs:**
```bash
docker logs n8n --tail 50
```

**Common causes:**
1. **Database connection error**: Check DB_TYPE in docker-compose.yml
2. **Port already in use**: Check if another service uses port 5678
3. **Invalid encryption key**: Regenerate encryption key
4. **Memory issues**: Upgrade to larger instance type

### Issue: Cannot access n8n after setup

**Checklist:**
1. ✅ EC2 instance is running
2. ✅ Security Group allows ports 80, 443
3. ✅ Nginx is running: `sudo systemctl status nginx`
4. ✅ n8n container is running: `docker ps | grep n8n`
5. ✅ DNS resolves correctly: `nslookup automation.yourcompany.com`
6. ✅ SSL certificate is valid: `sudo certbot certificates`

**Test step by step:**
```bash
# 1. Local access (on EC2)
curl http://localhost:5678
# Should return HTML

# 2. Through Nginx (on EC2)
curl http://localhost:80
# Should return HTML

# 3. Via domain (from your computer)
curl http://automation.yourcompany.com
# Should redirect to HTTPS or return HTML

# 4. HTTPS (from your computer)
curl https://automation.yourcompany.com
# Should return HTML with valid certificate
```

---

## Next Steps

### Initial Setup
1. Access your n8n instance: `https://automation.yourcompany.com`
2. Complete the setup wizard
3. Create admin account
4. **Save credentials securely!**

### Security Hardening
1. Restrict Security Group to your IP only:
   ```bash
   MY_IP=$(curl -s ifconfig.me)
   aws ec2 authorize-security-group-ingress \
     --group-id $SG_ID \
     --protocol tcp --port 443 --cidr $MY_IP/32
   
   aws ec2 revoke-security-group-ingress \
     --group-id $SG_ID \
     --protocol tcp --port 443 --cidr 0.0.0.0/0
   ```

2. Enable HTTP Basic Auth in Nginx (optional extra layer)

3. Set up AWS CloudWatch alarms for instance monitoring

### Expand with Subdomain

Create additional services on same domain:
```bash
# Example: Add API subdomain
api.yourcompany.com → Same Elastic IP
shop.yourcompany.com → Different IP or external service (CNAME)
```

### Upgrade to PostgreSQL

For production with high workflow volume:
1. Launch RDS PostgreSQL instance
2. Update docker-compose.yml with PostgreSQL configuration
3. Migrate data from SQLite

---

## Maintenance

### Weekly
- Check n8n logs: `docker logs n8n --tail 100`
- Verify backups in S3: `aws s3 ls s3://your-backup-bucket/`

### Monthly
- Review AWS billing dashboard
- Update n8n: `docker-compose pull && docker-compose up -d`
- Verify SSL certificate expiration: `sudo certbot certificates`

### Quarterly
- Review and rotate credentials
- Check for AWS security updates
- Review and optimize instance size based on usage

---

## Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [AWS EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [Route 53 Developer Guide](https://docs.aws.amazon.com/route53/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Docker Compose Reference](https://docs.docker.com/compose/)

---

## Support

For issues specific to:
- **n8n**: [n8n Community Forum](https://community.n8n.io/)
- **AWS**: [AWS Support Center](https://console.aws.amazon.com/support/)
- **Let's Encrypt**: [Let's Encrypt Community](https://community.letsencrypt.org/)

---

**Last Updated:** February 2026
**Author:** DevOps Documentation
**License:** MIT
