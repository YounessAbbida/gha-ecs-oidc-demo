data "aws_availability_zones" "available" {
  state = "available"

  # Regular AZs only (no Local Zones or Wavelength Zones).
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.project_name
  cidr = var.vpc_cidr
  azs  = local.azs

  # /24 per subnet: 10.20.0.0/24 and 10.20.1.0/24 public, 10.20.10.0/24 and 10.20.11.0/24 private.
  public_subnets  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  # One NAT gateway for both AZs: cheaper, but egress depends on a single AZ.
  # Acceptable for a demo; use one per AZ in production.
  enable_nat_gateway = true
  single_nat_gateway = true

  # The module adopts the default security group and strips all its rules.
  manage_default_security_group = true
}
