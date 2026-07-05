#!/bin/bash

set -e

case "$iacType" in

  s3WithCdn)
    TEMPLATE_PATH="aws/cloudformations/templates/s3withCdn/s3WithCdn.yaml"
    STACK_NAME="${environment}-${product}-${service}-s3WithCdn"
    ;;

  secretManager)
    TEMPLATE_PATH="aws/cloudformations/templates/secretmanager/secretmanager.yaml"
    STACK_NAME="${environment}-${product}-${service}"
    ;;
  vpc)
    TEMPLATE_PATH="aws/cloudformations/templates/vpc/vpc.yaml"
    STACK_NAME="${environment}-${product}-${service}"
    ;;
  postgresql)
    TEMPLATE_PATH="aws/cloudformations/templates/postgresql/postgresql.yaml"
    STACK_NAME="${environment}-${product}-${service}"
    ;;
  ec2)
    TEMPLATE_PATH="aws/cloudformations/templates/ec2/ec2.yaml"
    STACK_NAME="${environment}-${product}-${service}"
    ;;
  *)
    echo "ERROR: Unknown iacType value: '$iacType'"
    echo "Enter Valid iacType"
    exit 1
    ;;
esac

echo "Starting CloudFormation deployment for stack: ${STACK_NAME}"
aws cloudformation deploy \
    --region ap-south-1 \
    --stack-name "${STACK_NAME}" \
    --template-file "${TEMPLATE_PATH}" \
    --parameter-overrides \
      environment="${environment}" \
      product="${product}" \
      service="${service}" \
      iacType="${service}" \
    --capabilities CAPABILITY_IAM \
    --capabilities CAPABILITY_NAMED_IAM

echo "Deployment completed successfully!"