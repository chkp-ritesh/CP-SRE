#!/bin/bash

if [ "$1" == "-h" ] || [ "$1" == "--help" ]
then
  echo "Usage: ./sxdns-execute.sh [aws profile] [service name] [environment]"
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
    gimme-aws-creds --profile $AWS_PROFILE
fi

TASK_ID=$(aws ecs list-tasks --service-name $SERVICE_NAME --cluster $ENV-micro-services --region us-east-1 --profile $AWS_PROFILE | jq -r '.taskArns[0]' | cut -d'/' -f3)
echo "Executing into container in task - $TASK_ID"

aws ecs execute-command --region us-east-1 --cluster $ENV-micro-services --task $TASK_ID \
    --container $SERVICE_NAME-$ENV --command "sh" --interactive --profile $AWS_PROFILE

sleep 10s

./saferx-dns-cli

sleep 5s

echo "example lookup results:"
echo "rpc truenorthnetworks-cxXd11b10U A 72.95.93.87"
