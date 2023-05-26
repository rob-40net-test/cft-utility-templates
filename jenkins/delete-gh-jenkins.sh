#!/bin/bash

# Script to remove a repo within the FortinetCloudCSE org and remove the corresponding Jenkins job..
# Ensure you've downloaded the jenkins-cli.jar to your home directory and that your Jenkins access token
# is retrievable at ~/.jenkins-cli..

# Usage: ./delete-gh-jenkins.sh <Your Jenkins user id> <Name of Repo/Pipeline>

CL_ARR=($@)

[[ " ${CL_ARR[*]} " =~ "-h" ]] && echo "Usage: ./setup-gh-jenkins.sh <Your Jenkins user id> <Name of Repo/Job>" && exit 0

[[ "${#CL_ARR[@]}" -ne 2 ]] && \
  echo "Usage: ./setup-gh-jenkins.sh <Your Jenkins user id> <Name of Repo/Job>" && \
  exit 0

JENKINS_USER_ID=${CL_ARR[0]}
REPO_NAME=${CL_ARR[1]}

# Delete Jenkins job
echo "Deleting job..."
java -jar ~/jenkins-cli.jar -s https://jenkins.fortinetcloudcse.com:8443/ -auth $JENKINS_USER_ID:$(cat ~/.jenkins-cli) delete-job $REPO_NAME
[[ "$?" == "0" ]] && echo "Deleted Jenkins job $REPO_NAME" || echo "Error deleting Jenkins pipeline..."

# Delete github repo
echo "Deleting repo..."
gh repo delete FortinetCloudCSE/$REPO_NAME
[[ "$?" == "0" ]] || echo "Error deleting repo..."
