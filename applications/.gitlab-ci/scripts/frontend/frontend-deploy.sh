#!/bin/bash

set -e

S3_BUCKET_NAME="${environment}-${product}-${service}-bucket"

echo "Deploying to ${S3_BUCKET_NAME}"

aws s3 sync \
  win-web/apps/web/dist/ \
  s3://${S3_BUCKET_NAME} \
  --delete

ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account \
  --output text)

for DIST_ID in $(aws cloudfront list-distributions \
  --query 'DistributionList.Items[*].Id' \
  --output text); do

  TAGS=$(aws cloudfront list-tags-for-resource \
    --resource arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID})

  if echo "$TAGS" | grep -q "$environment" && \
     echo "$TAGS" | grep -q "$product" && \
     echo "$TAGS" | grep -q "$service"; then

      DISTRIBUTION_ID=$DIST_ID
      break
  fi
done

if [ -n "$DISTRIBUTION_ID" ]; then
  echo "Invalidating CloudFront Distribution: $DISTRIBUTION_ID"

  aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths "/*"
else
  echo "No matching CloudFront distribution found"
  exit 1
fi