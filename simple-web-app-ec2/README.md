# CloudFormation script to launch simple web app for FortiDAST demo

## Parameters


| Parameter      | Description                                                             |
| ---------------| ------------------------------------------------------------------------|
| InstanceType   | EC2 intstance type (i.e. t3.small)                                      |
| KeyPairName    | Name of an AWS key pair (i.e. my-key-pair)                              |
| AppVPC         | VPC logical ID (i.e. vpc-abcd1234)                                      |
| FortiDASTUUID  | FortiDAST App UUID as found under 'Scans Policy' in FortiDAST console.  |
| ElasticIPAlloc | Elastic IP allocation ID (i.e. eipalloc-1234abcd5678)                   |


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
