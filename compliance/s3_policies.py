import boto3
import json

# Initialize boto3 client
s3 = boto3.client("s3")

# Get list of all buckets
response = s3.list_buckets()
buckets = [bucket["Name"] for bucket in response["Buckets"]]

for bucket in buckets:
    print(f"Applying secure transport policy to bucket: {bucket}")

    # Define bucket policy
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "DenyHTTPRequests",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:*",
                "Resource": [
                    f"arn:aws:s3:::{bucket}",
                    f"arn:aws:s3:::{bucket}/*"
                ],
                "Condition": {
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            },
            {
                "Sid": "DenyNonSigV4Requests",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:*",
                "Resource": [
                    f"arn:aws:s3:::{bucket}",
                    f"arn:aws:s3:::{bucket}/*"
                ],
                "Condition": {
                    "StringNotEquals": {
                        "s3:SignatureVersion": "AWS4-HMAC-SHA256"
                    }
                }
            }
        ]
    }

    # Convert policy to JSON
    policy_json = json.dumps(policy)

    # Apply the bucket policy
    try:
        s3.put_bucket_policy(Bucket=bucket, Policy=policy_json)
        print(f"✅ Policy applied to {bucket}")
    except Exception as e:
        print(f"❌ Failed to apply policy to {bucket}: {e}")

