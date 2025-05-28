import boto3
import json
import os

ses = boto3.client('ses')

def lambda_handler(event, context):
    template_name = os.environ['SES_TEMPLATE']
    config_set = os.environ['SES_CONFIG_SET']
    sender = f"{os.environ['SES_SENDER_NAME']} <{os.environ['SES_SENDER']}>"

    destinations = []
    for row in event:
        destinations.append({
            'Destination': {'ToAddresses': [row['email']]},
            'ReplacementTemplateData': json.dumps({
                "first_name": row['first_name'],
                "last_name": row['last_name']
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
