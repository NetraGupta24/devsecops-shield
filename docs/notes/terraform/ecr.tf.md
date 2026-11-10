# `terraform/ecr.tf`

**What it does:** Creates the ECR repository `splitease`, the private Docker registry that holds
**only images that passed every gate**.
- `image_tag_mutability = "IMMUTABLE"`: once `build-17` exists it can never be overwritten. A tag
  always identifies exactly one image, which is essential for trustworthy rollbacks and audits.
- **Lifecycle policy:** keep the newest 5 images and expire older ones (keeps storage cost ~0).
- `force_delete = true`: `terraform destroy` can delete the repository even if it contains images.

**How it connects:** Jenkins pushes here. EC2 (user data and Ansible) pulls from here using the
instance role.
