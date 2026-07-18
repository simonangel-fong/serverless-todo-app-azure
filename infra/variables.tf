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

variable "function_app_zip_path" {
  description = "Path to the Function App deployment package (zip) built by CI. Supplied via -var on every apply; no default since a fresh zip must exist for each deploy. IMPORTANT: Terraform's change detection on zip_deploy_file compares the path string only, not file content/hash -- if CI passes the same fixed path on every run, a deploy with new code but an unchanged path will silently no-op. The path/filename must be unique per run (e.g. CI should embed a content hash or timestamp in it)."
  type        = string
}
