# n8n on AWS with Route 53 Domain - Infrastructure as Code (Terraform)

Fully automated deployment of n8n on AWS using Terraform. This approach is reproducible, version-controlled, and follows infrastructure as code best practices.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Repository Structure](#repository-structure)
4. [Quick Start](#quick-start)
5. [Detailed Setup](#detailed-setup)
6. [Configuration](#configuration)
7. [Deployment](#deployment)
8. [Post-Deployment](#post-deployment)
9. [Management](#management)
10. [Troubleshooting](#troubleshooting)
11. [Cost Management](#cost-management)

---

## Prerequisites

### Required Software
- **Terraform** >= 1.0 ([Installation Guide](https://developer.hashicorp.com/terraform/downloads))
- **AWS CLI** >= 2.0 ([Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html))
- **Git** (for version control)

### AWS Requirements
- AWS Account with billing enabled
- AWS CLI configured with credentials
- Domain name ideas (will be registered via Route 53)
- Credit card for domain registration

### Verify Prerequisites

```bash
# Check Terraform
terraform version
# Should show: Terraform v1.x.x

# Check AWS CLI
aws --version
# Should show: aws-cli/2.x.x

# Verify AWS credentials
aws sts get-caller-identity
# Should return your AWS account ID and user info
```

---

## Architecture Overview

This Terraform configuration creates:

```
┌─────────────────────────────────────────────────────────┐
│                     AWS Account                          │
│                                                           │
│  ┌──────────────┐      ┌──────────────┐                 │
│  │  Route 53    │      │     VPC      │                 │
│  │              │      │              │                 │
│  │ DNS Records  │─────▶│  Security    │                 │
│  │ Hosted Zone  │      │   Groups     │                 │
│  └──────────────┘      └──────────────┘                 │
│         │                      │                         │
│         │                      ▼                         │
│         │              ┌──────────────┐                 │
│         └─────────────▶│  Elastic IP  │                 │
│                        └──────────────┘                 │
│                                │                         │
│                                ▼                         │
│                        ┌──────────────┐                 │
│                        │ EC2 Instance │                 │
│                        │              │                 │
│                        │  - Docker    │                 │
│                        │  - n8n       │                 │
│                        │  - Nginx     │                 │
│                        │  - Certbot   │                 │
│                        └──────────────┘                 │
│                                │                         │
│                                ▼                         │
│                        ┌──────────────┐                 │
│                        │  S3 Bucket   │                 │
│                        │  (Backups)   │                 │
│                        └──────────────┘                 │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

**Resources Created:**
- Route 53 Hosted Zone (DNS management)
- Elastic IP (permanent IP address)
- EC2 Instance (t3.small, Amazon Linux 2023)
- Security Group (firewall rules)
- IAM Role & Instance Profile (for S3 access)
- S3 Bucket (for backups)
- User Data Script (automated setup)

---

## Repository Structure

```
n8n-terraform/
├── README.md
├── main.tf                    # Main infrastructure definition
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── terraform.tfvars          # Your configuration values
├── user_data.sh              # EC2 initialization script
└── .gitignore                # Git ignore file
```

---

## Quick Start

### 1. Clone or Create Project Directory

```bash
mkdir n8n-terraform
cd n8n-terraform
```

### 2. Download Terraform Files

Download these files to your `n8n-terraform/` directory:
- `main.tf`
- `variables.tf`
- `outputs.tf`
- `user_data.sh`
- `terraform.tfvars.example`

### 3. Configure Variables

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

### 4. Deploy

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy infrastructure
terraform apply
```

**Total deployment time:** ~10-15 minutes

---

## Detailed Setup

### Step 1: Create Terraform Configuration Files

#### 1.1: Create `variables.tf`

```hcl
# variables.tf
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "domain_name" {
  description = "Domain for n8n (e.g., automation.yourcompany.com)"
  type        = string
}

variable "n8n_encryption_key" {
  description = "n8n encryption key (32 hex characters)"
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "Email for SSL certificate notifications"
  type        = string
}

variable "ssh_key_name" {
  description = "Name of existing AWS key pair for SSH access"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 20
}
```

#### 1.2: Create `main.tf`

See the attached `main.tf` file for complete infrastructure definition.

Key resources:
- AWS Provider configuration
- Data sources (VPC, Subnets, AMI)
- Security Groups (with proper ingress/egress rules)
- IAM Role for S3 backup access
- S3 Bucket with lifecycle policies
- EC2 Instance with Elastic IP
- User Data for automated setup

#### 1.3: Create `outputs.tf`

```hcl
# outputs.tf
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.n8n.id
}

output "instance_public_ip" {
  description = "Public IP address (Elastic IP)"
  value       = aws_eip.n8n.public_ip
}

output "domain_name" {
  description = "Domain configured for n8n"
  value       = var.domain_name
}

output "n8n_url" {
  description = "n8n access URL"
  value       = "https://${var.domain_name}"
}

output "ssh_command" {
  description = "SSH command to connect to instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_eip.n8n.public_ip}"
}

output "s3_backup_bucket" {
  description = "S3 bucket for backups"
  value       = aws_s3_bucket.n8n_backups.id
}
```

#### 1.4: Create `user_data.sh`

See the attached `user_data.sh` file for the complete initialization script.

This script runs on first boot and:
1. Updates system packages
2. Installs Docker, Nginx, Certbot
3. Configures n8n with Docker Compose
4. Sets up Nginx reverse proxy
5. Obtains SSL certificate
6. Configures automated backups
7. Sets up health monitoring

#### 1.5: Create `terraform.tfvars`

```hcl
# terraform.tfvars - YOUR CONFIGURATION

aws_region  = "us-east-1"
environment = "production"

# Domain Configuration
# IMPORTANT: This should be a subdomain you want to use
# Example: "automation.yourcompany.com" or "n8n.yourcompany.com"
domain_name = "automation.yourcompany.com"

# Admin Email (for SSL certificate notifications)
admin_email = "your-email@example.com"

# SSH Key
# Create this in AWS EC2 Console → Key Pairs first
ssh_key_name = "your-aws-key-pair-name"

# n8n Encryption Key
# Generate with: openssl rand -hex 32
n8n_encryption_key = "REPLACE_WITH_32_HEX_CHARACTERS"

# Optional: Customize instance
# instance_type = "t3.small"  # or "t3.micro" for lower cost
# volume_size   = 20          # GB
```

#### 1.6: Create `.gitignore`

```
# .gitignore
# Terraform files
.terraform/
*.tfstate
*.tfstate.backup
.terraform.lock.hcl

# Sensitive files
terraform.tfvars
*.pem
*.key

# OS files
.DS_Store
Thumbs.db

# Backup files
*.bak
*~
```

---

## Configuration

### Generate Encryption Key

```bash
# Generate a secure 32-character hex key
openssl rand -hex 32

# Example output: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0
# Copy this to terraform.tfvars
```

### Create SSH Key Pair (if you don't have one)

```bash
# Via AWS Console:
# EC2 → Key Pairs → Create key pair
# Name: n8n-key
# Type: RSA
# Format: .pem
# Download and save to ~/.ssh/

# Or via AWS CLI:
aws ec2 create-key-pair \
  --key-name n8n-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/n8n-key.pem

chmod 400 ~/.ssh/n8n-key.pem
```

### Domain Considerations

**Important:** You must register the root domain separately!

Terraform will:
- Create DNS records for your subdomain
- NOT register the root domain (must be done manually or via Route 53 Console)

**Two scenarios:**

**Scenario A: You don't own the domain yet**
1. First, register the domain manually:
   - Route 53 → Register domain → Complete registration
   - Wait for verification and activation
2. Then use Terraform to create subdomain DNS records

**Scenario B: You already own the domain**
1. Ensure the domain is in Route 53
2. Terraform will create DNS records for the subdomain

---

## Deployment

### Step 1: Initialize Terraform

```bash
cd n8n-terraform

# Download provider plugins and modules
terraform init

# Should show: "Terraform has been successfully initialized!"
```

### Step 2: Validate Configuration

```bash
# Check for syntax errors
terraform validate

# Should show: "Success! The configuration is valid"
```

### Step 3: Plan Deployment

```bash
# Preview all changes
terraform plan

# Review output carefully
# Should show ~10-15 resources to be created
```

**Expected resources:**
- aws_security_group.n8n_instance
- aws_security_group.n8n_database (if using RDS)
- aws_iam_role.n8n_instance
- aws_iam_role_policy.n8n_s3_backup
- aws_iam_instance_profile.n8n
- aws_s3_bucket.n8n_backups
- aws_eip.n8n
- aws_instance.n8n
- (Optional) aws_route53_record.n8n

### Step 4: Apply Configuration

```bash
# Deploy infrastructure
terraform apply

# Review plan one more time
# Type: yes

# Deployment takes ~5-10 minutes
```

**What happens during deployment:**
1. Security groups created
2. IAM roles configured
3. S3 bucket created
4. EC2 instance launched
5. Elastic IP allocated and associated
6. User data script executes:
   - System updates
   - Docker installation
   - n8n deployment
   - Nginx configuration
   - SSL certificate obtainment
   - Backup setup

### Step 5: Monitor Deployment

```bash
# Get instance ID from output
INSTANCE_ID=$(terraform output -raw instance_id)

# Watch user data script execution
aws ec2 get-console-output --instance-id $INSTANCE_ID

# Or SSH to instance and check logs
ssh -i ~/.ssh/your-key.pem ec2-user@$(terraform output -raw instance_public_ip)
tail -f /var/log/user-data.log
```

### Step 6: Verify DNS (if using Route 53 records)

```bash
# Check DNS resolution
nslookup $(terraform output -raw domain_name)

# Should return the Elastic IP
```

---

## Post-Deployment

### 1. Complete Manual DNS Setup (if needed)

If Terraform didn't create Route 53 records (domain registered elsewhere):

```bash
# Get your Elastic IP
terraform output instance_public_ip

# Manually create A record:
# automation.yourcompany.com → [Elastic IP]
```

### 2. Wait for SSL Certificate

The user data script automatically requests SSL certificate from Let's Encrypt.

**Check progress:**
```bash
# SSH to instance
ssh -i ~/.ssh/your-key.pem ec2-user@$(terraform output -raw instance_public_ip)

# Check user data log
tail -100 /var/log/user-data.log

# Look for: "Successfully received certificate"
```

**Timing:**
- DNS must be resolving (2-10 minutes)
- Then SSL certificate process runs
- Total: 15-30 minutes for full deployment

### 3. Access n8n

```bash
# Get n8n URL
terraform output n8n_url

# Open in browser
# Example: https://automation.yourcompany.com
```

**You should see:**
- ✅ Green padlock (valid SSL)
- ✅ n8n setup wizard
- ✅ No security warnings

### 4. Complete n8n Setup

1. Create admin account
2. Configure basic settings
3. **Save credentials securely!**

### 5. Verify Backups

```bash
# List S3 bucket
aws s3 ls $(terraform output -raw s3_backup_bucket)/

# Should show backup files (after first scheduled backup at 2 AM)
```

---

## Management

### View Infrastructure State

```bash
# List all resources
terraform state list

# Show resource details
terraform state show aws_instance.n8n

# View outputs
terraform output
```

### Update Configuration

```bash
# Edit terraform.tfvars or main.tf
nano terraform.tfvars

# Preview changes
terraform plan

# Apply changes
terraform apply
```

**Common updates:**
- Change instance type (scale up/down)
- Modify security group rules
- Update backup retention

### Update n8n

```bash
# SSH to instance
ssh -i ~/.ssh/your-key.pem ec2-user@$(terraform output -raw instance_public_ip)

# Update n8n
cd ~/n8n-deployment
docker-compose pull
docker-compose up -d

# Verify
docker-compose logs -f n8n
```

### Destroy Infrastructure

⚠️ **Warning:** This deletes everything!

```bash
# Preview what will be deleted
terraform plan -destroy

# Destroy all resources
terraform destroy

# Type: yes

# Manually delete:
# - Registered domain (if you want to keep it)
# - S3 backup bucket (if it has contents, must be emptied first)
```

**Before destroying:**
```bash
# Backup n8n data
ssh ec2-user@$(terraform output -raw instance_public_ip)
cd ~/n8n-deployment
./backup.sh

# Download backup locally
scp -i ~/.ssh/your-key.pem \
  ec2-user@$(terraform output -raw instance_public_ip):~/n8n-backups/* \
  ./local-backup/
```

---

## Advanced Configuration

### Use RDS PostgreSQL Instead of SQLite

Add to `main.tf`:

```hcl
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

resource "aws_db_instance" "n8n" {
  identifier_prefix = "n8n-db-"
  
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_encrypted    = true
  
  db_name  = "n8n"
  username = "n8nadmin"
  password = var.db_password
  
  vpc_security_group_ids = [aws_security_group.n8n_database.id]
  
  backup_retention_period = 7
  skip_final_snapshot    = false
  
  tags = {
    Name        = "n8n-database"
    Environment = var.environment
  }
}

# Update user_data.sh to use PostgreSQL
# DB_TYPE=postgresdb
# DB_POSTGRESDB_HOST=${aws_db_instance.n8n.address}
```

### Multiple Environments

```bash
# Create workspace for staging
terraform workspace new staging
terraform workspace new production

# Switch workspace
terraform workspace select staging

# Each workspace has separate state
terraform apply
```

### Remote State Backend

Store Terraform state in S3 (recommended for teams):

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "n8n/terraform.tfstate"
    region = "us-east-1"
    
    # Optional: State locking
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### Multiple Subdomains

```hcl
# Add more subdomains
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.n8n.public_ip]
}

resource "aws_route53_record" "admin" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "admin.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.n8n.public_ip]
}
```

---

## Troubleshooting

### Terraform Errors

#### Error: "Error creating Security Group"

**Cause:** Security group with same name exists

**Solution:**
```bash
# Find existing security group
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=n8n-*"

# Delete it or change name in main.tf
aws ec2 delete-security-group --group-id sg-xxxxx
```

#### Error: "Error launching source instance: InvalidKeyPair.NotFound"

**Cause:** SSH key pair doesn't exist

**Solution:**
```bash
# Create key pair
aws ec2 create-key-pair --key-name your-key-name

# Or update terraform.tfvars with existing key name
```

#### Error: "Error applying plan: timeout while waiting for state to become 'running'"

**Cause:** Instance failed to start, usually user data script error

**Solution:**
```bash
# Check instance console output
aws ec2 get-console-output --instance-id i-xxxxx

# Look for errors in user data execution
```

### Deployment Issues

#### n8n not accessible after 15 minutes

**Check:**
1. **DNS resolving?**
   ```bash
   nslookup automation.yourcompany.com
   ```

2. **Instance running?**
   ```bash
   aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id) \
     --query 'Reservations[0].Instances[0].State.Name'
   ```

3. **User data completed?**
   ```bash
   ssh ec2-user@$(terraform output -raw instance_public_ip)
   tail -50 /var/log/user-data.log
   ```

4. **Docker running?**
   ```bash
   ssh ec2-user@$(terraform output -raw instance_public_ip)
   docker ps
   ```

#### SSL certificate not obtained

**Symptoms:**
- Can access via HTTP but not HTTPS
- Browser shows "connection refused" on HTTPS

**Solution:**
```bash
# SSH to instance
ssh ec2-user@$(terraform output -raw instance_public_ip)

# Check certbot logs
sudo tail -100 /var/log/letsencrypt/letsencrypt.log

# Manually retry
sudo certbot --nginx -d automation.yourcompany.com

# Common issues:
# - DNS not resolving yet (wait 5-10 more minutes)
# - Port 80 blocked (check security group)
# - Wrong email in config
```

### State Management Issues

#### Error: "state lock"

**Cause:** Another Terraform process is running or crashed

**Solution:**
```bash
# Force unlock (use ID from error message)
terraform force-unlock LOCK_ID
```

#### Lost state file

**Prevention:**
```bash
# Always use remote backend for production
# Add to main.tf:
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "n8n/terraform.tfstate"
    region = "us-east-1"
  }
}
```

**Recovery:**
```bash
# If you have resources but lost state:
terraform import aws_instance.n8n i-xxxxx
terraform import aws_eip.n8n eipalloc-xxxxx
# ... import each resource
```

---

## Cost Management

### View Estimated Costs

```bash
# Use Infracost (optional tool)
# https://www.infracost.io/

infracost breakdown --path .

# Shows monthly cost estimate for all resources
```

### Monitor Actual Costs

```bash
# AWS Cost Explorer API
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=TAG,Key=Name

# Or use AWS Console:
# Billing Dashboard → Cost Explorer
```

### Cost Optimization

#### 1. Right-size Instance

```hcl
# In terraform.tfvars
instance_type = "t3.micro"  # Half the cost of t3.small

# Apply changes
terraform apply
```

#### 2. Use Reserved Instances

```bash
# Purchase RI for 1-3 years (40-60% savings)
# AWS Console → EC2 → Reserved Instances → Purchase
```

#### 3. Stop instance when not in use

```bash
# Stop instance (Elastic IP costs $3.60/month when stopped)
aws ec2 stop-instances --instance-ids $(terraform output -raw instance_id)

# Start when needed
aws ec2 start-instances --instance-ids $(terraform output -raw instance_id)
```

#### 4. Lifecycle Policies

S3 backups automatically deleted after 30 days (configurable in main.tf)

---

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/terraform.yml
name: Terraform

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - uses: hashicorp/setup-terraform@v2
      with:
        terraform_version: 1.5.0
    
    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: us-east-1
    
    - name: Terraform Init
      run: terraform init
    
    - name: Terraform Validate
      run: terraform validate
    
    - name: Terraform Plan
      run: terraform plan
      
    - name: Terraform Apply
      if: github.ref == 'refs/heads/main'
      run: terraform apply -auto-approve
```

---

## Best Practices

### 1. Version Control

```bash
# Initialize git repository
git init
git add .
git commit -m "Initial n8n infrastructure"

# Push to GitHub
git remote add origin https://github.com/yourusername/n8n-terraform.git
git push -u origin main
```

### 2. Sensitive Data

```bash
# NEVER commit terraform.tfvars
# Use environment variables or AWS Secrets Manager

export TF_VAR_n8n_encryption_key="$(openssl rand -hex 32)"
export TF_VAR_admin_email="your@email.com"

terraform apply
```

### 3. State Backup

```bash
# Backup state file regularly
terraform state pull > backup-$(date +%Y%m%d).tfstate

# Store in separate S3 bucket
aws s3 cp backup-*.tfstate s3://my-state-backups/
```

### 4. Tagging Strategy

```hcl
locals {
  common_tags = {
    Project     = "n8n"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "DevOps Team"
    CostCenter  = "Automation"
  }
}

resource "aws_instance" "n8n" {
  # ...
  tags = merge(
    local.common_tags,
    {
      Name = "n8n-${var.environment}"
    }
  )
}
```

### 5. Documentation

Document changes in `CHANGELOG.md`:

```markdown
# Changelog

## [1.0.0] - 2024-02-16
### Added
- Initial Terraform configuration
- EC2 instance with n8n
- Automated SSL setup
- S3 backup configuration

## [1.1.0] - 2024-02-20
### Changed
- Upgraded to t3.small instance
- Added CloudWatch monitoring
```

---

## Migration

### From Manual to Terraform

If you have an existing manual setup:

```bash
# 1. Import existing resources
terraform import aws_instance.n8n i-xxxxx
terraform import aws_eip.n8n eipalloc-xxxxx
terraform import aws_security_group.n8n_instance sg-xxxxx

# 2. Verify state matches reality
terraform plan
# Should show: "No changes"

# 3. Now you can manage with Terraform
```

### From DuckDNS to Route 53

```bash
# 1. Register domain in Route 53
# 2. Update terraform.tfvars with new domain
# 3. Apply changes
terraform apply

# 4. Update DNS when ready (minimal downtime)
# 5. Old DuckDNS will continue working during transition
```

---

## Additional Resources

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [n8n Self-Hosting Guide](https://docs.n8n.io/hosting/)

---

**Last Updated:** February 2026
**Terraform Version:** 1.5+  
**AWS Provider Version:** 5.0+  
**License:** MIT