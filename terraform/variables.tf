variable "aws_region" {
  description = "AWS region for provisioning resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "instance_type" {
  description = "EC2 instance type (free-tier eligible in region)"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Project name tag and identifier prefix"
  type        = string
  default     = "devops-fullstack-app"
}
