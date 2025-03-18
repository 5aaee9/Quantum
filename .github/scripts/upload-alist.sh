#!/usr/bin/env bash

TARGET_FILENAME="$1"
TARGET_FILE_PATH="$2"

ALIST_TOKEN=$(curl -s "${ALIST_UPLOAD_DOMAIN}/api/auth/login/hash" \
  -H 'Content-Type: application/json;charset=UTF-8' \
  --data-raw '{"username":"'${ALIST_USERNAME}'","password":"'${ALIST_PASSWORD}'","otp_code":""}' | jq .data.token -r)

curl -X PUT "${ALIST_UPLOAD_DOMAIN}/api/fs/put" \
  -H "Authorization: $ALIST_TOKEN" \
  -H "File-Path: $TARGET_FILE_PATH/"$(basename $TARGET_FILENAME) \
  -T "$TARGET_FILENAME"
