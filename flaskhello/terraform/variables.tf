variable "aws_region" {
    description = "AWS region"
    type = string
    default = "us-east-1"
}

variable "app_name" {
    description = "Application name"
    type = string
    default = "flaskhello"
}

variable "ecr_repository_uri" {
    description = "ECR repository URI"
    type = string
}

variable "terraform_state_bucket" {
    description = "S3 bucket for Terraform state"
    type = string
}
