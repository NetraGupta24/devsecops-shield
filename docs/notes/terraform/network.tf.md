# `terraform/network.tf`

**What it does:** Builds the private network (VPC) the app lives in:
- **VPC** `10.20.0.0/16`: your own isolated network inside AWS.
- **2 public subnets** in **2 Availability Zones** (separate data centres). An ALB *requires* two
  AZs, and it also means one data-centre failure doesn't take the site down.
- **Internet Gateway** + **route table** (`0.0.0.0/0 → IGW`): lets the subnets reach the internet.
- `map_public_ip_on_launch = true`: instances get a public IP.

**Why no private subnets / NAT Gateway (cost decision):** instances in private subnets need a NAT
Gateway (~$30+/month) to reach ECR/SSM. Instead the instances sit in public subnets, but the **app
security group** only accepts app traffic from the ALB and SSH from your IP. That is good enough for
this project and is listed as a trade-off.
