# ECR Module - Docker image registry for model serving

resource "aws_ecr_repository" "model" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # Allow terraform destroy even with images

  image_scanning_configuration {
    scan_on_push = false  # Disable to reduce costs
  }

  tags = {
    Name    = var.repository_name
    Project = var.project_name
  }
}

# Lifecycle policy - keep only latest 5 images
resource "aws_ecr_lifecycle_policy" "model" {
  repository = aws_ecr_repository.model.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
