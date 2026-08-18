# Digital Terrarium

A tiny browser ecosystem with production-grade infrastructure hiding underneath the glass.

The live terrarium remains a zero-install interactive experience, while this repository now contains a complete serverless reference architecture for saving habitats, advancing climate cycles, and observing ecosystem health.

## Why Terraform is the main language

Terraform is intentionally more than half of the codebase. It owns the actual system:

- encrypted habitat state in DynamoDB
- a Go Lambda simulation API
- API Gateway routing and throttling
- EventBridge climate-cycle schedules
- S3 + CloudFront static hosting
- CloudWatch dashboards, alarms, and structured logs
- reusable habitat and observatory modules
- least-privilege IAM and configurable retention
- optional custom-domain wiring

The remaining runtime is deliberately polyglot:

- **Go** — deterministic habitat simulation service
- **Lua** — portable ecological rules and species interactions
- **HTML/CSS/JavaScript** — tactile browser terrarium

## Architecture

Browser terrarium → CloudFront → S3  
Browser terrarium → HTTP API → Go Lambda → DynamoDB  
EventBridge → Go Lambda → climate cycle  
CloudWatch ← logs, alarms, and ecosystem metrics

## Local use

Open index.html directly, or serve the directory with any static server.

The cloud stack is optional. The terrarium remains playable without an AWS account.

## Deploy the infrastructure

Requirements:

- Terraform 1.7+
- AWS credentials for an isolated development account
- Go 1.22+ to build the Lambda package

Typical flow:

    cd api
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap .
    zip lambda.zip bootstrap
    cd ..
    terraform init
    terraform plan -var-file=examples/terraform.tfvars
    terraform apply -var-file=examples/terraform.tfvars

Copy examples/terraform.tfvars.example to examples/terraform.tfvars and adjust it before applying.

## API

- GET /health — service and cycle status
- GET /habitats/{id} — read a habitat
- PUT /habitats/{id} — save browser state
- POST /habitats/{id}/cycle — advance one ecological cycle
- DELETE /habitats/{id} — remove a habitat

## Design principles

1. The browser experience works alone.
2. Cloud state is opt-in and disposable.
3. Every cycle is deterministic when given the same seed.
4. Infrastructure is observable by default.
5. Cost ceilings are explicit.
6. The strange little plants remain the point.
