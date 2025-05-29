import boto3
import json
import os
import random
import hashlib
from urllib.parse import urlencode, urlparse, urlunparse, parse_qs


ses = boto3.client('ses')
s3 = boto3.client('s3')

def hash_digest(value: str) -> str:
    return hashlib.sha256(value.encode('utf-8')).hexdigest()

def lambda_handler(event, context):
    template_name = os.environ['SES_TEMPLATE']
    config_set = os.environ['SES_CONFIG_SET']
    sender = f"{os.environ['SES_SENDER_NAME']} <{os.environ['SES_SENDER']}>"
    
    bucket = os.environ['CAMPAIGN_METADATA_S3']
    campaign = event['campaign_name']
    key = f"{campaign}.json"
    
    # S3 API call
    campaign_data = s3.get_object(Bucket=bucket, Key=key)
    
    # Campaign data extraction
    campaign_data_json = json.loads(campaign_data['Body'].read().decode('utf-8'))
    variants = campaign_data_json['content']

    # Prepare weighted choices
    variant_choices = []
    for v in variants:
        weight = int(v['weight'])
        variant_choices.extend([v] * weight)
    
    destinations = []
    for row in event['batch']:
        # Randomly select a variant based on weights
        chosen_variant = random.choice(variant_choices)
        
        # Generate anonymized identifiers
        campaign_digest = hash_digest(campaign)
        variant_digest = hash_digest(chosen_variant['variant'])
        email_digest = hash_digest(row['email'])
        
        # Build URL with anonymized digests as query parameters
        original_url = chosen_variant['cta_link']
        parsed_url = urlparse(original_url)
        original_query = parse_qs(parsed_url.query)

        # Add anonymized parameters
        original_query.update({
            "cid": [campaign_digest],
            "vid": [variant_digest],
            "uid": [email_digest]
        })

        new_query_string = urlencode(original_query, doseq=True)
        new_cta_link = urlunparse(parsed_url._replace(query=new_query_string))        
    
        destinations.append({
            'Destination': {'ToAddresses': [row['email']]},
            'ReplacementTemplateData': json.dumps({
                "first_name": row['first_name'],
                "last_name": row['last_name'],
                "subject": chosen_variant['subject'],
                "body_content": chosen_variant['body_content'],
                "cta_link": new_cta_link,
                "cta_text": chosen_variant['cta_text'],
            })
        })

    if destinations:
        return ses.send_bulk_templated_email(
            Source=sender,
            Template=template_name,
            Destinations=destinations,
            ConfigurationSetName=config_set,
            DefaultTemplateData=json.dumps({"first_name": "Friend", "last_name": ""})
        )
