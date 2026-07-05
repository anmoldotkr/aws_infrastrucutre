#!/bin/bash

set -e

# System & Region Configurations
AWS_ACCOUNT_ID="xxxxxxxxxxx"
AWS_REGION="xxxxxxxxxxxxx"
ENV_FILE_PATH="/tmp/.env.runtime"

# Target directory /home/ubuntu/app
COMPOSE_DIR="/home/ubuntu/app"
COMPOSE_FILE_PATH="${COMPOSE_DIR}/docker-compose.yml"

echo "Deploying to Environment: ${environment}"
echo "Product:                  ${product}"
echo "Service:                  ${service}"
echo "AWS Region:               ${AWS_REGION}"

if [ -z "${TARGET_INSTANCE_ID}" ]; then
  echo "Error: TARGET_INSTANCE_ID is not defined."
  exit 1
fi

# Derive Resource and Dynamic Paths
SECRET_APP_VAR="${environment}/${product}/creds"
SECRET_DB_VAR="${environment}/${product}/db/creds"
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${environment}-${product}-${service}"
SHORT_SHA=${CI_COMMIT_SHORT_SHA:-$(echo "$CI_COMMIT_SHA" | cut -c1-5)}

echo "Image URI target:         ${IMAGE_URI}:${SHORT_SHA}"

# 1. Build a pure Shell script on the runner
echo "Drafting raw remote installation asset..."

cat << 'EOF' > /tmp/remote_payload.sh
#!/bin/bash
set -e
echo '------------------------------------------'
echo 'Executing Deployment Script Inside Target EC2'
echo '------------------------------------------'

echo 'Pruning old unused build layer caches to free up disk space...'
docker system prune -f

echo 'Logging in to ECR inside EC2...'
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

echo 'Pulling pre-built image version from ECR...'
docker pull $IMAGE_URI:$SHORT_SHA

echo 'Clearing out old configurations & preparing directory...'
rm -f $ENV_FILE_PATH
rm -f $COMPOSE_FILE_PATH

echo 'Fetching App Variables from Secrets Manager...'
aws secretsmanager get-secret-value --secret-id $SECRET_APP_VAR --region $AWS_REGION --query SecretString --output text | jq -r 'to_entries | .[] | .key + "=" + .value' >> $ENV_FILE_PATH

echo 'Fetching DB Credentials from Secrets Manager...'
aws secretsmanager get-secret-value --secret-id $SECRET_DB_VAR --region $AWS_REGION --query SecretString --output text | jq -r 'to_entries | .[] | .key + "=" + .value' >> $ENV_FILE_PATH

chmod 600 $ENV_FILE_PATH

echo 'Determining Environment...'
if [ "$environment" = "dev" ]; then APP_NODE_ENV="development"; else APP_NODE_ENV="production"; fi

echo 'Generating docker-compose.yml on-the-fly at /home/ubuntu/app...'
cat << 'INNER_EOF' > $COMPOSE_FILE_PATH
version: '3.8'
networks:
  app_network:
    name: '$environment-$product-network'
    driver: bridge

volumes:
  xyz_redis_data:

services:
  xyz-node:
    container_name: '$environment-$product-xyz-node'
    image: '$IMAGE_URI:$SHORT_SHA'
    restart: always
    ports:
      - '3000:3000'
    environment:
      - REDIS_HOST=redis
    env_file:
      - '$ENV_FILE_PATH'
    networks:
      - app_network
    depends_on:
      redis:
        condition: service_healthy

  redis:
    image: redis:7-alpine
    container_name: '$environment-$product-redis'
    restart: unless-stopped
    command: redis-server --appendonly yes
    ports:
      - '6380:6379'
    volumes:
      - xyz_redis_data:/data
    networks:
      - app_network
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 5s
INNER_EOF

echo 'Ensuring proper permissions for /home/ubuntu/app...'
chown -R ubuntu:ubuntu $COMPOSE_DIR || true

echo 'Deploying update via Docker Compose...'
docker compose -f $COMPOSE_FILE_PATH up -d

echo 'Pruning older dangling images...'
docker image prune -f
EOF

# Inject all your standard dynamic properties via sed
sed -i "s|\$AWS_ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" /tmp/remote_payload.sh
sed -i "s|\$AWS_REGION|${AWS_REGION}|g" /tmp/remote_payload.sh
sed -i "s|\$ENV_FILE_PATH|${ENV_FILE_PATH}|g" /tmp/remote_payload.sh
sed -i "s|\$COMPOSE_DIR|${COMPOSE_DIR}|g" /tmp/remote_payload.sh
sed -i "s|\$COMPOSE_FILE_PATH|${COMPOSE_FILE_PATH}|g" /tmp/remote_payload.sh
sed -i "s|\$SECRET_APP_VAR|${SECRET_APP_VAR}|g" /tmp/remote_payload.sh
sed -i "s|\$SECRET_DB_VAR|${SECRET_DB_VAR}|g" /tmp/remote_payload.sh
sed -i "s|\$IMAGE_URI|${IMAGE_URI}|g" /tmp/remote_payload.sh
sed -i "s|\$SHORT_SHA|${SHORT_SHA}|g" /tmp/remote_payload.sh
sed -i "s|\$environment|${environment}|g" /tmp/remote_payload.sh
sed -i "s|\$product|${product}|g" /tmp/remote_payload.sh

# jq automatically construct the JSON properly
echo "Compiling final secure ssm_parameters.json payload..."
jq -R -s 'split("\n") | {commands: (.[:-1])}' /tmp/remote_payload.sh > ssm_parameters.json
# Dispatch the payload to AWS Systems Manager
echo "Sending execution parameters to AWS SSM for Instance: ${TARGET_INSTANCE_ID}..."

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "${TARGET_INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --parameters file://ssm_parameters.json \
  --region "${AWS_REGION}" \
  --query "Command.CommandId" \
  --output text)

echo "SSM Command successfully sent! Command ID: ${COMMAND_ID}"

# Live Poll Command Execution Status
echo "Waiting for execution to complete on EC2..."
while true; do
  STATUS=$(aws ssm list-command-invocations \
    --command-id "${COMMAND_ID}" \
    --details \
    --region "${AWS_REGION}" \
    --query "CommandInvocations[0].Status" \
    --output text)
  
  echo "Current Deployment Status: [${STATUS}]"
  
  if [ "$STATUS" = "Success" ]; then
    echo "Deployment successfully finished on the EC2 instance. File generated at: /home/ubuntu/app/docker-compose.yml"
    break
  elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Cancelled" ] || [ "$STATUS" = "TimedOut" ]; then
      echo "Deployment execution failed on the EC2 instance."
      echo "Fetching live stderr logs from the EC2 target..."
      
      #This line pulls the exact error description from the EC2 instance
      aws ssm get-command-invocation \
        --command-id "${COMMAND_ID}" \
        --instance-id "${TARGET_INSTANCE_ID}" \
        --region "${AWS_REGION}" \
        --query "{Error:StandardErrorContent,Output:StandardOutputContent}" \
        --output json
    exit 1
  fi
  sleep 7
done