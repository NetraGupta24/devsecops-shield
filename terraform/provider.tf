# Which Terraform and AWS provider versions this project uses, and the AWS
# region. Run Terraform from your laptop as your own IAM user (never root).

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # State is stored locally in terraform/terraform.tfstate (gitignored).
}

provider "aws" {
  region = var.aws_region

  # Added to every resource that supports tags, so all project resources are
  # easy to find (and to check on the bill).
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  colors = toset(["blue", "green"])

  # Before the first release nothing is live. We mark GREEN as "live" so that
  # the first pipeline run deploys to BLUE (the idle colour) and switches
  # traffic to it. From then on the pipeline alternates blue <-> green.
  initial_live_color = "green"
  initial_idle_color = "blue"

  account_id   = data.aws_caller_identity.current.account_id
  ecr_registry = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  param_prefix = "/${var.project}"
}
