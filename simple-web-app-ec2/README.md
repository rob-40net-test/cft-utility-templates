# CloudFormation script to launch simple web app for FortiDAST demo

## Configure AWS creds

```
export AWS_DEFAULT_REGION=us-east-1 && export AWS_PROFILE=user-admin
```

## Launch stack

```
aws cloudformation create-stack \
  --stack-name fortidast-demo \
  --template-body file://simple-web-app-ec2.yaml \
  --parameters file://simple-web-app-params.json \
  --capabilities CAPABILITY_NAMED_IAM
```
