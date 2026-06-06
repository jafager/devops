# Configure the AWS provider and remote state backend
terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }

    backend "s3" {
        bucket = "jafager-sandbox-flaskhello-terraform-state"
        key = "flaskhello/terraform.tfstate"
        region = "us-east-1"
    }
}

provider "aws" {
    region = var.aws_region

    default_tags {
        tags = {
            Project = var.app_name
            ManagedBy = "terraform"
        }
    }
}


# VPC and networking
resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = "${var.app_name}-vpc"
    }
}

resource "aws_subnet" "public" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "${var.aws_region}a"
    map_public_ip_on_launch = true

    tags = {
        Name = "${var.app_name}-public-subnet"
    }
}

resource "aws_internet_gateway" "main" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${var.app_name}-igw"
    }
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }

    tags = {
        Name = "${var.app_name}-public-rt"
    }
}

resource "aws_route_table_association" "public" {
    subnet_id = aws_subnet.public.id
    route_table_id = aws_route_table.public.id
}


# Security group — allows inbound on port 5000 and all outbound
resource "aws_security_group" "flaskhello" {
    name = "${var.app_name}-sg"
    description = "Security group for ${var.app_name}"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 5000
        to_port = 5000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "${var.app_name}-sg"
    }
}


# IAM role for ECS task execution
resource "aws_iam_role" "ecs_task_execution" {
    name = "${var.app_name}-ecs-task-execution"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = {
                Service = "ecs-tasks.amazonaws.com"
            }
        }]
    })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
    role = aws_iam_role.ecs_task_execution.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# ECS cluster
resource "aws_ecs_cluster" "main" {
    name = "${var.app_name}-cluster"

    tags = {
        Name = "${var.app_name}-cluster"
    }
}


# ECS task definition
resource "aws_ecs_task_definition" "flaskhello" {
    family = var.app_name
    network_mode = "bridge"
    requires_compatibilities = ["EC2"]
    execution_role_arn = aws_iam_role.ecs_task_execution.arn
    cpu = "256"
    memory = "256"

    container_definitions = jsonencode([{
        name = var.app_name
        image = "${var.ecr_repository_uri}:latest"

        portMappings = [{
            containerPort = 5000
            hostPort = 5000
            protocol = "tcp"
        }]

        logConfiguration = {
            logDriver = "awslogs"
            options = {
                "awslogs-group" = "/ecs/${var.app_name}"
                "awslogs-region" = var.aws_region
                "awslogs-stream-prefix" = "ecs"
            }
        }
    }])
}


# CloudWatch log group for container logs
resource "aws_cloudwatch_log_group" "flaskhello" {
    name = "/ecs/${var.app_name}"
    retention_in_days = 7

    tags = {
        Name = "${var.app_name}-logs"
    }
}


# EC2 instance for ECS
resource "aws_instance" "ecs_host" {
    ami = data.aws_ami.ecs_optimized.id
    instance_type = "t3.micro"
    subnet_id = aws_subnet.public.id
    vpc_security_group_ids = [aws_security_group.flaskhello.id]
    iam_instance_profile = aws_iam_instance_profile.ecs_host.name

    user_data = base64encode(
        "#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config"
    )

    tags = {
        Name = "${var.app_name}-ecs-host"
    }
}


# Look up the latest ECS-optimized AMI
data "aws_ami" "ecs_optimized" {
    most_recent = true
    owners = ["amazon"]

    filter {
        name = "name"
        values = ["al2023-ami-ecs-hvm-*-x86_64"]
    }
}


# IAM instance profile for EC2 ECS host
resource "aws_iam_role" "ecs_host" {
    name = "${var.app_name}-ecs-host"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = {
                Service = "ec2.amazonaws.com"
            }
        }]
    })
}

resource "aws_iam_role_policy_attachment" "ecs_host" {
  role = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_host" {
  name = "${var.app_name}-ecs-host"
  role = aws_iam_role.ecs_host.name
}


# ECS service
resource "aws_ecs_service" "flaskhello" {
  name = "${var.app_name}-service"
  cluster = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.flaskhello.arn
  desired_count = 1
  launch_type = "EC2"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent = 100

  tags = {
    Name = "${var.app_name}-service"
  }
}


### GitHub Actions

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# IAM role that GitHub Actions assumes via OIDC
resource "aws_iam_role" "github_actions" {
    name = "${var.app_name}-github-actions"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Principal = {
                Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
            }
            Action = "sts:AssumeRoleWithWebIdentity"
            Condition = {
                StringEquals = {
                    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
                }
                StringLike = {
                    "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
                }
            }
        }]
    })
}

# Policy allowing ECR push and ECS deployment
resource "aws_iam_policy" "github_actions" {
  name = "${var.app_name}-github-actions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.app_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${var.app_name}-cluster/${var.app_name}-service"
      },
      {
        Effect = "Allow"
        Action = [
            "ecs:DescribeTaskDefinition",
            "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
            "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.app_name}-ecs-task-execution"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
    role = aws_iam_role.github_actions.name
    policy_arn = aws_iam_policy.github_actions.arn
}
