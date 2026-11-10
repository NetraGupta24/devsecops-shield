# SSM Parameter Store (standard parameters are free): the pipeline's shared
# memory about what is deployed where.
#   /splitease/live_color        which colour gets production traffic
#   /splitease/<colour>/image_tag  which image each colour runs ("none" = nothing yet)
#   /splitease/chaos_mode        "true" enables /crash and /cpu on NEW deployments
# Jenkins changes the values, so Terraform only creates them and then ignores
# their values.

resource "aws_ssm_parameter" "live_color" {
  name        = "${local.param_prefix}/live_color"
  description = "Colour that receives production traffic on port 80"
  type        = "String"
  tier        = "Standard"
  value       = local.initial_live_color

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "image_tag" {
  for_each = local.colors

  name        = "${local.param_prefix}/${each.key}/image_tag"
  description = "ECR image tag the ${each.key} environment runs"
  type        = "String"
  tier        = "Standard"
  value       = "none"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "chaos_mode" {
  name        = "${local.param_prefix}/chaos_mode"
  description = "true = enable the /crash and /cpu chaos endpoints (demos only)"
  type        = "String"
  tier        = "Standard"
  value       = "false"

  lifecycle {
    ignore_changes = [value]
  }
}
