# Deploying the ECS Stack

This CloudFormation template will provision an ECS cluster for deployment of a containerized web application.

## Prereqs

- VPC with a public subnet (it's route table containing a route to an internet gateway)

- AWS CLI installed

- An ECR repository with an image to deploy to the ECS cluster (if you don't have one, you can follow the instructions below to create one)

- An unallocated elastic IP

## Setup
 
- First, set your region and profile for the AWS CLI.
 
 ```
 export AWS_DEFAULT_REGION=<your region> && \ 
    export AWS_PROFILE=<your profile as configured in your local AWS credentials file>
 ```
- If you don't already have an ECR cluster you'd like to integrate, you can create one with the following command. Be sure to note down the repositoryUri displayed in the output:
 
 ```
 aws ecr create-repository --repository-name <ECR Repo Name> \
    --image-scanning-configuration scanOnPush=true
 ```
 
- Navigate to the directory containing the application you'd like to containerize and push to your ECR repository, and run the following:

 ```
 aws ecr get-login-password --region <region> | docker login --username AWS \
    --password-stdin <Your AWS acct number>.dkr.ecr.<region>.amazonaws.com
 docker build -t <image name>:<image tag> .
 docker tag <image name>:<image tag> <repositoryUri>:latest
 docker push <repositoryUri>:latest
 ```
- Navigate back to this repository and specify the needed parameters in ecs-app-params.json: 

 ```
 [
        {
                "ParameterKey": "ECRRepo",
                "ParameterValue": "<repositoryUri from output above>"
        },
        {
                "ParameterKey": "ECRRepoName",
                "ParameterValue": "<name of repository or repositoryName from output above>"
        },
        {
                "ParameterKey": "KeyPair",
                "ParameterValue": "<the name a key pair from your account>"
        },
        {
                "ParameterKey": "AppVPC",
                "ParameterValue": "vpc-123abc456"
        },
        {
                "ParameterKey": "AppSubnet",
                "ParameterValue": "subnet-789efg101112h"
        },
        {
                "ParameterKey": "AllowedCidr",
                "ParameterValue": "0.0.0.0/0"
        },
        {
                "ParameterKey": "ElasticIPAlloc",
                "ParameterValue": "eipalloc-1234abcd5678efgh9"
        }
]
 ```

- Deploy the stack with the following command:

 ```
 aws cloudformation create-stack --stack-name <enter a name for your stack here> \
    --template-body file://./ecs-app-template.yml --parameters file://./ecs-app-params.json \ 
	--capabilities CAPABILITY_NAMED_IAM
 ```

- The app should be accessible at the elastic IP associated with the allocation ID you specified in the parameter file.

- The stack is configured to automatically update the cluster upon the push of a new image version to the ECR repository, so you can navigate back to the repository containing your application, build a new image and push it, and the stack will update automatically. For example:
 
 ```
 docker build -t <image name>:<image tag> .
 docker tag <image name>:<image tag> <repositoryUri>:latest
 docker push <repositoryUri>:latest
 ```
 
- To delete the stack, you can run:
 
 ```
 aws cloudformation delete-stack --stack-name <your stack name>
 ```
