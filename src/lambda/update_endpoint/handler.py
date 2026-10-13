"""update-endpoint — invoked by the REST API, runs a translation through the
fine-tuned, gender-debiased model endpoint.

Flow:
1. the Translation service web app POSTs {"text", "source_lang", "target_lang"}
   to the REST API's /translate resource, which proxies the request here;
2. this Lambda invokes the "Fine-tuned model endpoint (unbiased)" Lambda,
   playing the role of a SageMaker runtime `invoke_endpoint` call against the
   model that was fine-tuned by the bias-mitigation training notebook;
3. the translated text and the list of applied bias mitigations are returned
   back through the REST API to the web app.
"""
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")
MODEL_ENDPOINT_FUNCTION_NAME = os.environ["MODEL_ENDPOINT_FUNCTION_NAME"]

lambda_client = boto3.client("lambda", region_name=REGION, endpoint_url=os.environ.get("AWS_ENDPOINT_URL"))


def _invoke_model_endpoint(text, source_lang, target_lang):
    """Simulates `sagemaker_runtime.invoke_endpoint(EndpointName=..., Body=...)`."""
    payload = {"text": text, "source_lang": source_lang, "target_lang": target_lang}

    response = lambda_client.invoke(
        FunctionName=MODEL_ENDPOINT_FUNCTION_NAME,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload).encode("utf-8"),
    )

    return json.loads(response["Payload"].read())


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
    }


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"message": "Request body must be valid JSON."})

    text = body.get("text")
    if not text:
        return _response(400, {"message": "text is required."})

    source_lang = body.get("source_lang", "en")
    target_lang = body.get("target_lang", "es")

    model_response = _invoke_model_endpoint(text, source_lang, target_lang)

    return _response(
        200,
        {
            "source_text": text,
            "source_lang": source_lang,
            "target_lang": target_lang,
            "translated_text": model_response.get("translated_text"),
            "bias_mitigations_applied": model_response.get("bias_mitigations_applied", []),
            "model": model_response.get("model"),
        },
    )
