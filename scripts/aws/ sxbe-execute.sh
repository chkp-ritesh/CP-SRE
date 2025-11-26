#!/bin/bash

if [ "$1" == "-h" ] || [ "$1" == "--help" ]
then
  echo "Usage: ./sxbe-execute.sh [aws profile] [service name] [environment]"
  echo "aws profile - for example CoreDev / CoreDevAdmins"
  echo "service name - saferx-backend / saferx-backend-cli"
  echo "environment - vader / staging / production / etc."
  exit 0
fi

AWS_PROFILE=$1
SERVICE_NAME=$2
ENV=$3

aws sts get-caller-identity --profile $AWS_PROFILE > /dev/null 2>&1

if [ $? -eq 0 ]; then
    :
else
    echo "Getting AWS credentials"
    aws sso login --profile $AWS_PROFILE
    #gimme-aws-creds --profile $AWS_PROFILE
fi

TASK_ID=$(aws ecs list-tasks --service-name $SERVICE_NAME --cluster $ENV-ec2-micro-services --region us-east-1 --profile $AWS_PROFILE | jq -r '.taskArns[0]' | cut -d'/' -f3)
echo "Executing into container in task - $TASK_ID"

echo "aws ecs execute-command --cluster $CLUSTER --task $TASK_ID --container $SERVICE_NAME-$ENV --command "$SHELL" --interactive --profile $AWS_PROFILE --region us-east-1"

aws ecs execute-command --region us-east-1 --cluster $ENV-ec2-micro-services --task $TASK_ID \
    --container $SERVICE_NAME-$ENV --command "bash" --interactive --profile $AWS_PROFILE
