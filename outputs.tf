output "cloudfront_domain_name" {
  description = "CDN domain name serving the Translation service static web app."
  value       = aws_cloudfront_distribution.static_website.domain_name
}

output "translation_api_endpoint" {
  description = "Invoke URL of the REST API's /translate endpoint."
  value       = "${aws_api_gateway_stage.translation.invoke_url}/translate"
}

output "update_endpoint_function_name" {
  description = "Name of the update-endpoint Lambda invoked by the REST API."
  value       = aws_lambda_function.update_endpoint.function_name
}

output "model_endpoint_function_name" {
  description = "Name of the Lambda simulating the fine-tuned, unbiased translation model (SageMaker-style) endpoint."
  value       = aws_lambda_function.model_endpoint.function_name
}

output "model_artifacts_bucket" {
  description = "Name of the S3 bucket holding the fine-tuned, gender-debiased translation model artifacts."
  value       = aws_s3_bucket.model_artifacts.bucket
}

output "static_website_bucket" {
  description = "Name of the S3 bucket holding the Translation service static web app."
  value       = aws_s3_bucket.static_website.bucket
}
