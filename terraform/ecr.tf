# ECR: the private registry that stores ONLY images that passed every gate.

resource "aws_ecr_repository" "app" {
  name = var.project

  # Immutable tags: once build-17 is pushed it can never be overwritten, so a
  # tag always means exactly one image (important for rollback and audits).
  image_tag_mutability = "IMMUTABLE"

  # Lets `terraform destroy` delete the repository even if it still has images.
  force_delete = true

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep only the newest 5 images to stay within the free storage allowance.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
