#!/usr/bin/env python3
"""
EC2 script: Upload contents of a local zip file to S3.
Processes zip members in-memory—no extraction to disk.
"""

import argparse
import os
import sys
import zipfile

import boto3

S3_BUCKET = "argorand-uploads"  # Hardcoded bucket name


def upload_zip_contents_to_s3(
    zip_path: str,
    bucket: str,
    prefix: str = "",
    dry_run: bool = False,
) -> tuple[int, int]:
    """Upload each file in zip to S3. Returns (uploaded_count, skipped_count)."""
    s3 = boto3.client("s3")
    uploaded = 0
    skipped = 0

    with zipfile.ZipFile(zip_path, "r") as zf:
        for name in zf.namelist():
            if name.endswith("/"):
                skipped += 1
                continue

            s3_key = f"{prefix}{name}".lstrip("/") if prefix else name

            if dry_run:
                print(f"  [dry-run] would upload: {name} -> s3://{bucket}/{s3_key}")
                uploaded += 1
                continue

            with zf.open(name) as member:
                s3.upload_fileobj(member, Bucket=bucket, Key=s3_key)
            print(f"  uploaded: {name} -> s3://{bucket}/{s3_key}")
            uploaded += 1

    return uploaded, skipped


def main():
    parser = argparse.ArgumentParser(
        description="Upload contents of a local zip file to S3"
    )
    parser.add_argument("zip_path", help="Path to the local zip file")
    parser.add_argument(
        "-b", "--bucket",
        default=S3_BUCKET,
        help=f"S3 bucket (default: {S3_BUCKET})",
    )
    parser.add_argument(
        "-p", "--prefix",
        default="",
        help="S3 key prefix for uploaded objects (e.g. 'uploads/2025/')",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List what would be uploaded without uploading",
    )
    args = parser.parse_args()

    if not os.path.isfile(args.zip_path):
        print(f"File not found: {args.zip_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Uploading contents of {args.zip_path} to s3://{args.bucket}/{args.prefix or '(root)'}...")
    uploaded, skipped = upload_zip_contents_to_s3(
        args.zip_path,
        bucket=args.bucket,
        prefix=args.prefix,
        dry_run=args.dry_run,
    )
    print(f"Done. Uploaded {uploaded} files, skipped {skipped} directories.")


if __name__ == "__main__":
    main()
