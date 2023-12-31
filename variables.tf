variable "github_token" {
  description = "GitHub token for AWS CodePipeline"
  type        = string
  default     = ""
}

variable "terraform_state_bucket" {
  description = "S3 bucket for storing Terraform state files"
  type        = string
  default     = ""
}
