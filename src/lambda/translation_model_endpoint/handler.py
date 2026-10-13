"""Fine-tuned model endpoint (unbiased) — simulated SageMaker inference endpoint.

This Lambda plays the role of a SageMaker "invoke_endpoint" inference
endpoint hosting the fine-tuned translation LLM that was trained to mitigate
gender bias (see notebooks/train_debias_translation.ipynb). The floci
emulator does not expose a SageMaker runtime, so in this local scaffold the
endpoint is a Lambda function instead of a real `sagemaker-runtime`
endpoint; in a real AWS account you would replace this function with an
Amazon SageMaker real-time endpoint and call it with
`sagemaker_runtime.invoke_endpoint(EndpointName=..., Body=...)`.

Flow:
1. load the gender-debiasing glossary artifact that the training notebook
   uploaded to the model-artifacts S3 bucket (the deployed, fine-tuned
   model's weights, here simplified to a lookup table);
2. run a toy "translation" of the input text, swapping any gendered terms
   found in the glossary for their gender-neutral equivalents;
3. return the translated text together with the list of bias mitigations
   that were applied, mimicking an inference response payload.
"""
import json
import os

import boto3
from botocore.exceptions import ClientError

REGION = os.environ.get("REGION", "us-east-1")
MODEL_ARTIFACTS_BUCKET = os.environ["MODEL_ARTIFACTS_BUCKET"]
DEBIAS_GLOSSARY_KEY = os.environ["DEBIAS_GLOSSARY_KEY"]

s3 = boto3.client("s3", region_name=REGION, endpoint_url=os.environ.get("AWS_ENDPOINT_URL"))

# Fallback glossary used until the training notebook has deployed a
# fine-tuned artifact to the model-artifacts bucket.
_DEFAULT_GLOSSARY = {
    "he said": "they said",
    "she said": "they said",
    "chairman": "chairperson",
    "waitress": "waiter",
    "policeman": "police officer",
    "mankind": "humankind",
}


def _load_debias_glossary():
    try:
        response = s3.get_object(Bucket=MODEL_ARTIFACTS_BUCKET, Key=DEBIAS_GLOSSARY_KEY)
        return json.loads(response["Body"].read())
    except ClientError:
        # No fine-tuned artifact deployed yet - fall back to the built-in glossary.
        return _DEFAULT_GLOSSARY


def _translate(text, target_lang, glossary):
    translated = text
    mitigations = []

    for biased_term, debiased_term in glossary.items():
        if biased_term.lower() in translated.lower():
            translated = translated.replace(biased_term, debiased_term)
            mitigations.append({"from": biased_term, "to": debiased_term})

    return f"[{target_lang}] {translated}", mitigations


def lambda_handler(event, context):
    """Simulated `invoke_endpoint` request/response for the fine-tuned model."""
    text = event.get("text", "")
    target_lang = event.get("target_lang", "es")

    glossary = _load_debias_glossary()
    translated_text, bias_mitigations = _translate(text, target_lang, glossary)

    return {
        "translated_text": translated_text,
        "bias_mitigations_applied": bias_mitigations,
        "model": "fine-tuned-translation-model-unbiased",
    }
