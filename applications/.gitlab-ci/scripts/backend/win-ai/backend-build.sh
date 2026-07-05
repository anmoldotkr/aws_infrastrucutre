#!/bin/bash

set -e

echo "Environment: ${environment}"
echo "Product:     ${product}"
echo "Service:     ${service}"

AWS_ACCOUNT_ID="xxxxxxxxxxxx"
AWS_REGION="xxxxxxxxxxxxx"

if [ -z "${service}" ]; then
  echo "Error: 'service' variable is not defined. Cannot determine what to build."
  exit 1
fi

echo "Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

SHORT_SHA=${CI_COMMIT_SHORT_SHA:-$(echo "$CI_COMMIT_SHA" | cut -c1-5)}
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${environment}-${product}-${service}"

echo "service: xyz-ai. Builing and pushing to ${environment}-${product}-${service}"

BUILDX_NO_DEFAULT_ATTESTATIONS=1 docker build \
    -f xyz-ai/docker/Dockerfile \
    --build-arg environment="${environment}" \
    --build-arg product="${product}" \
    --build-arg service="${service}" \
    -t "${IMAGE_URI}:${SHORT_SHA}" xyz-ai

echo "Pushing ${service} image to ECR..."
docker push "${IMAGE_URI}:${SHORT_SHA}"

echo "Build and push for ${service} completed successfully!"