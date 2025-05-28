import boto3
import csv
import io
import os

s3 = boto3.client('s3')

def lambda_handler(event, context):
    campaign = event['campaign_name']
    bucket = os.environ['S3_BUCKET']
    key = f"{campaign}.csv"

    s3_obj = s3.get_object(Bucket=bucket, Key=key)
    csv_content = s3_obj['Body'].read().decode('utf-8')
    reader = list(csv.DictReader(io.StringIO(csv_content)))

    # Chunk into groups of 50
    chunk_size = 50
    return [reader[i:i + chunk_size] for i in range(0, len(reader), chunk_size)]
