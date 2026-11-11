provider "aws" {
  region = var.aws_region

  # Every resource created by this project gets these tags.
  # Handy for finding (and cleaning up) everything later in the console.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
