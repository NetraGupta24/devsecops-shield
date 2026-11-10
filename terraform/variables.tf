variable "aws_region" {
  description = "AWS region for everything."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Name used for (and tagged on) every resource."
  type        = string
  default     = "splitease"
}

variable "my_ip" {
  description = "Your public IP as a /32 CIDR, e.g. 203.0.113.10/32. Only this IP may use SSH (22) and the ALB test listener (8080)."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && endswith(var.my_ip, "/32")
    error_message = "my_ip must be a single IPv4 address in CIDR form ending in /32."
  }
}

variable "alert_email" {
  description = "Email address that receives CloudWatch alarm notifications (you must confirm the subscription email)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. Free-plan eligible types only."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "Use t3.micro (default) or t3.small only."
  }
}

variable "ssh_public_key_path" {
  description = "Public half of the SSH key Ansible uses to log in to the instances."
  type        = string
  default     = "~/.ssh/splitease-deploy.pub"
}

variable "vpc_cidr" {
  description = "IP range of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "app_port" {
  description = "Port the SplitEase container listens on."
  type        = number
  default     = 5000
}

variable "health_check_grace_period" {
  description = "Seconds a new instance gets to boot (user data) before failed ALB health checks make the ASG replace it. t3 in 'standard' credit mode starts with 0 CPU credits, so boot runs at baseline speed."
  type        = number
  default     = 300
}
