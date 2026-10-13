# ─── S3: model artifacts (bias-mitigation training output) + static website ─

resource "aws_s3_bucket" "model_artifacts" {
  bucket = "${local.name_prefix}-${var.model_artifacts_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.model_artifacts_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "static_website" {
  bucket = "${local.name_prefix}-${var.static_website_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.static_website_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── IAM: role for the fine-tuned model endpoint Lambda ──────────────────────
#
# The floci emulator does not expose a SageMaker runtime, so the fine-tuned,
# unbiased translation model is simulated by a dedicated Lambda function that
# plays the role of a SageMaker "invoke_endpoint" inference endpoint: it loads
# the gender-debiasing glossary (the artifact produced by the training
# notebook) from the model-artifacts bucket and applies it to run inference.

resource "aws_iam_role" "model_endpoint" {
  name = "${local.name_prefix}-model-endpoint"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "model_endpoint_basic" {
  role       = aws_iam_role.model_endpoint.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "model_endpoint_s3" {
  name = "${local.name_prefix}-model-endpoint-s3"
  role = aws_iam_role.model_endpoint.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.model_artifacts.arn}/*"
    }]
  })
}

# ─── Lambda: fine-tuned model endpoint (unbiased) — simulated SageMaker
# "invoke_endpoint" inference endpoint for the gender-debiased translation
# model ─────────────────────────────────────────────────────────────────────

resource "null_resource" "model_endpoint_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/translation_model_endpoint/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} translation_model_endpoint"
  }
}

data "archive_file" "model_endpoint_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/translation_model_endpoint/handler.py"
  output_path = "${path.module}/.build/translation_model_endpoint.zip"

  depends_on = [null_resource.model_endpoint_package]
}

resource "aws_lambda_function" "model_endpoint" {
  function_name = "${local.name_prefix}-model-endpoint"
  role          = aws_iam_role.model_endpoint.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.model_endpoint_zip.output_path
  source_code_hash = data.archive_file.model_endpoint_zip.output_base64sha256

  environment {
    variables = {
      REGION                 = var.aws_region
      MODEL_ARTIFACTS_BUCKET = aws_s3_bucket.model_artifacts.bucket
      DEBIAS_GLOSSARY_KEY    = var.debias_glossary_key
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-model-endpoint"
  })

  depends_on = [
    aws_iam_role_policy_attachment.model_endpoint_basic,
    aws_iam_role_policy.model_endpoint_s3,
  ]
}

# ─── IAM: role for the update-endpoint Lambda (REST API integration) ────────

resource "aws_iam_role" "update_endpoint" {
  name = "${local.name_prefix}-update-endpoint"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "update_endpoint_basic" {
  role       = aws_iam_role.update_endpoint.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "update_endpoint_invoke_model" {
  name = "${local.name_prefix}-update-endpoint-invoke-model"
  role = aws_iam_role.update_endpoint.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.model_endpoint.arn
    }]
  })
}

# ─── Lambda: update-endpoint — invoked by the REST API, calls the fine-tuned
# model endpoint to run the translation and returns the response ────────────

resource "null_resource" "update_endpoint_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/update_endpoint/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} update_endpoint"
  }
}

data "archive_file" "update_endpoint_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/update_endpoint/handler.py"
  output_path = "${path.module}/.build/update_endpoint.zip"

  depends_on = [null_resource.update_endpoint_package]
}

resource "aws_lambda_function" "update_endpoint" {
  function_name = "${local.name_prefix}-update-endpoint"
  role          = aws_iam_role.update_endpoint.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.update_endpoint_zip.output_path
  source_code_hash = data.archive_file.update_endpoint_zip.output_base64sha256

  environment {
    variables = {
      REGION                       = var.aws_region
      MODEL_ENDPOINT_FUNCTION_NAME = aws_lambda_function.model_endpoint.function_name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-update-endpoint"
  })

  depends_on = [
    aws_iam_role_policy_attachment.update_endpoint_basic,
    aws_iam_role_policy.update_endpoint_invoke_model,
  ]
}

# ─── API Gateway: REST API used by the Translation service web app ──────────

resource "aws_api_gateway_rest_api" "translation" {
  name        = "${local.name_prefix}-translation-api"
  description = "REST API used by the Translation service web app to request gender-debiased translations."

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "translate" {
  rest_api_id = aws_api_gateway_rest_api.translation.id
  parent_id   = aws_api_gateway_rest_api.translation.root_resource_id
  path_part   = "translate"
}

resource "aws_api_gateway_method" "post_translate" {
  rest_api_id   = aws_api_gateway_rest_api.translation.id
  resource_id   = aws_api_gateway_resource.translate.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_translate" {
  rest_api_id             = aws_api_gateway_rest_api.translation.id
  resource_id             = aws_api_gateway_resource.translate.id
  http_method             = aws_api_gateway_method.post_translate.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.update_endpoint.invoke_arn
}

resource "aws_lambda_permission" "apigw_update_endpoint" {
  statement_id  = "AllowAPIGatewayInvokeUpdateEndpoint"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_endpoint.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.translation.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "translation" {
  rest_api_id = aws_api_gateway_rest_api.translation.id

  triggers = {
    redeployment = sha1(jsonencode([aws_api_gateway_integration.post_translate]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.post_translate]
}

resource "aws_api_gateway_stage" "translation" {
  rest_api_id   = aws_api_gateway_rest_api.translation.id
  deployment_id = aws_api_gateway_deployment.translation.id
  stage_name    = var.api_stage_name

  tags = local.common_tags
}

# ─── Translation service web app: uploaded to S3, delivered through CloudFront

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static_website.id
  key          = "index.html"
  content_type = "text/html"

  content = templatefile("${path.module}/web/index.html.tftpl", {
    project_name             = var.project_name
    translation_api_endpoint = "${aws_api_gateway_stage.translation.invoke_url}/translate"
  })
}

resource "aws_cloudfront_origin_access_control" "static_website" {
  name                              = "${local.name_prefix}-static-website-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "static_website" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "CDN for the ${var.project_name} Translation service web app"

  origin {
    domain_name              = aws_s3_bucket.static_website.bucket_regional_domain_name
    origin_id                = "static-website-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_website.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "static-website-s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}

resource "aws_s3_bucket_policy" "static_website_cloudfront" {
  bucket = aws_s3_bucket.static_website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipalReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.static_website.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.static_website.arn
        }
      }
    }]
  })
}
