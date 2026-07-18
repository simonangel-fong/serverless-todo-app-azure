variable "project_name" {
  description = "Short project name used for resource tagging."
  type        = string
  default     = "serverless-todoapp"
}

variable "environment" {
  description = "Deployment environment. Single environment for this project (see SPEC.md non-goals)."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags merged into the common tag set (project, environment, managed_by)."
  type        = map(string)
  default     = {}
}
