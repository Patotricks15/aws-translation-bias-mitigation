variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-translation-bias-mitigation"
}

variable "aws_region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

variable "static_website_bucket_name" {
  description = "Name of the S3 bucket hosting the Translation service static web app, served through CloudFront."
  type        = string
  default     = "static-website"
}

variable "model_artifacts_bucket_name" {
  description = "Name of the S3 bucket holding the fine-tuned, gender-debiased translation model artifacts produced by the training notebook."
  type        = string
  default     = "model-artifacts"
}

variable "api_stage_name" {
  description = "API Gateway deployment stage name for the translation REST API."
  type        = string
  default     = "dev"
}

variable "debias_glossary_key" {
  description = "S3 key, inside the model artifacts bucket, of the gender-debiasing glossary/artifact deployed to the fine-tuned model endpoint."
  type        = string
  default     = "fine-tuned-translation-model/debias_glossary.json"
}
