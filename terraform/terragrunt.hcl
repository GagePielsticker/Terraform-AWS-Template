locals {
  env_hcl     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_hcl.locals.environment

  project = "REPLACE_ME_PROJECT_NAME" #REPLACE THIS
  team    = "REPLACE_ME_TEAM_NAME" #REPLACE THIS
  region  = "us-east-1"

  common_tags = {
    project     = local.project
    team        = local.team
    region      = local.region
    environment = local.environment
  }
}

terraform {
  source = "${get_parent_terragrunt_dir()}/modules/sample-module"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "thryv-${local.environment}-infra-tf-state"
    key          = "${local.project}/terraform.tfstate"
    region       = local.region
    use_lockfile = true
    encrypt      = true
  }
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.10.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
      }
    }
  EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.region}"
      default_tags {
        tags = ${jsonencode(local.common_tags)}
      }
    }
  EOF
}
