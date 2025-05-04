#!/bin/bash

if ! aws sts get-caller-identity >/dev/null; then
    aws sso login >/dev/stderr
fi

if [[ -n $WAS_ACCOUNT_FILTER ]]; then
    echo "WAS_ACCOUNT_FILTER is set" >/dev/stderr
    echo "Filtering for lines that match regex: ${WAS_ACCOUNT_FILTER}" >/dev/stderr
    sleep 1
fi

profile=$(aws configure list-profiles | grep -E "${WAS_ACCOUNT_FILTER}" | fzf)
aws configure export-credentials --profile="${profile}" --format=env
echo "export AWS_PROFILE=${profile}"
region=$(aws configure get region --profile="${profile}")
echo "export AWS_REGION=${region}"

echo "" >/dev/stderr
echo "Exporting creds for $profile" >/dev/stderr
