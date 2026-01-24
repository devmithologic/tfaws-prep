# AWS & Terraform Learning

Personal repository for learning AWS and Terraform, working towards AWS Solutions Architect Associate certification.

## Structure

| Directory | Purpose |
|-----------|---------|
| `foundations/` | Core concepts and individual services |
| `projects/` | Multi-service mini-projects |
| `certification/` | SAA exam specific labs |
| `modules/` | Reusable Terraform modules |
| `sandbox/` | Quick experiments (may be messy) |
| `docs/` | Personal notes and cheatsheets |

## Progress

- [ ] Terraform basics
- [ ] IAM
- [ ] VPC
- [ ] EC2
- [ ] S3
- [ ] RDS
- [ ] Load Balancing
- [ ] Auto Scaling
- [ ] SAA Certification

## Setup

```bash
aws configure
# Verify
aws sts get-caller-identity
```

## Cost reminder

Always destroy resources after practice:

```bash
terraform destroy -auto-approve
```

### Template

```
foundations/aws-core-services/ec2/
├── README.md           # Qué aprendiste, comandos útiles
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example    # Ejemplo sin datos sensibles
└── diagram.png                 # Opcional, arquitectura visual