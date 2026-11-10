# `ansible/inventory/aws_ec2.yml`

**What it does:** A **dynamic inventory**. Instead of a fixed list of IP addresses (wrong as soon as
Auto Scaling replaces a server), Ansible asks the EC2 API each time: "which **running** instances
are tagged `Project=splitease`?". It groups them by their `Env` tag into **`env_blue`** and
**`env_green`** and connects to their public IPs.

It needs `boto3` (the AWS SDK for Python) and `ec2:DescribeInstances` permission, both present in
the Jenkins image and the Jenkins IAM policy. Try it: `ansible-inventory --graph`.
