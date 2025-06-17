#!/usr/bin/env python3

import boto3
import fnmatch
import json
import sys
import re
from datetime import datetime, timezone, timedelta

FILENAME_MASK = '*.tfstate.tflock'
OWNER_OF_INTEREST =r"mate@.*"
LOCK_MAX_AGE = timedelta(hours=1)

def list_matching_keys(bucket, mask):
    paginator = s3.get_paginator('list_objects_v2')
    keys = []
    for page in paginator.paginate(Bucket=bucket):
        for obj in page.get('Contents', []):
            key = obj['Key']
            if fnmatch.fnmatch(key, mask):
                keys.append(key)
    return keys

def is_lock_stale(bucket, f, owner):

    obj = s3.get_object(Bucket=bucket, Key=f)
    body = obj['Body'].read().decode('utf-8')
    try:
        data = json.loads(body)
    except Exception as e:
        print(f"Could not parse {obj} as JSON: {e}")
        return False

    # check the lock owner
    who = data.get("Who", "")
    if not re.match(owner, who):
        print(f"   lock {f} belongs to {who} (which does not match '{owner}')")
        return False

    # check the lock age
    created = data.get("Created")
    try:
        created_time = datetime.strptime(created.split('.')[0], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
        age = datetime.now(timezone.utc) - created_time
        if age < LOCK_MAX_AGE:
            print(f"   lock {f} age is just {age.seconds} seconds")
            return False
    except ValueError:
        # Handle microseconds that are not 6 digits (e.g., nanoseconds)
        print(f"Unable to parse timestamp {created}")
        return False

    print(f"   lock {f} belongs to {who} and has age {age.seconds} seconds and considered STALE")
    return True

def delete_obj(bucket, obj):
    s3.delete_object(Bucket=bucket, Key=obj)
    print(f"   object {f} DELETED")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <bucket-name>")
        sys.exit(1)

    bucket_name = sys.argv[1]

    s3 = boto3.client('s3')

    lock_files = list_matching_keys(bucket_name, FILENAME_MASK)
    print(f"Found {len(lock_files)} file(s) matching '{FILENAME_MASK}':")
    for f in lock_files:
        if is_lock_stale(bucket_name, f, OWNER_OF_INTEREST):
            delete_obj(bucket_name, f)
