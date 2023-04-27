#!/bin/bash

# Script to create a repo within FortinetCloudCSE from a template repo, add a webhook to trigger Jenkins builds, 
# create a pipeline in Jenkins, and trigger a manual first build. Ensure you've downloaded the jenkins-cli.jar 
# to your home directory.

# Add the -p flag to add build parameters if testing Terraform builds.

# Usage: ./setup-gh-jenkins.sh <Your Jenkins user id> <Name of Template Repo> <Name of New Repo> <Github username of collaborator to be added> [-p]

CL_ARR=$@

[[ " ${CL_ARR[*]} " =~ "-h" ]] && echo "Usage: ./setup-gh-jenkins.sh <Your Jenkins user id> <Name of Template Repo> <Name of New Repo> <Github username of collaborator to be added> [-p]" && exit 0

PPARAM="-p"
if [[ " ${CL_ARR[*]} " =~ $PPARAM ]]; then
  JCONF="template-config-params.xml"
  CL_ARR=($(echo "${CL_ARR[@]/$PPARAM}"))
else
  JCONF="template-config.xml"
  CL_ARR=($CL_ARR)
fi

[[ "${#CL_ARR[@]}" -ne 4 ]] && \
  echo "Usage: ./setup-gh-jenkins.sh <Your Jenkins user id> <Name of Template Repo> <Name of New Repo> <Github username of collaborator to be added> [-p]" && \
  exit 0

JENKINS_USER_ID=${CL_ARR[0]}
TEMPLATE_REPO_NAME=${CL_ARR[1]}
REPO_NAME=${CL_ARR[2]}
COLLAB=${CL_ARR[3]}

# Create repo
gh repo create FortinetCloudCSE/$REPO_NAME -p FortinetCloudCSE/$TEMPLATE_REPO_NAME --public
[[ "$?" == "0" ]] || echo "Error creating repo..."

# Add user to repo as Collaborator
gh api -X PUT repos/FortinetCloudCSE/$REPO_NAME/collaborators/$COLLAB
[[ "$?" == "0" ]] || echo "Error adding $COLLAB as collaborator..."

# Add branch protection rules
while : ; do  
  BR_CHECK=$(gh api /repos/FortinetCloudCSE/$REPO_NAME/branches | jq -r '.[] | select(.name=="main")')
  [[ -z "$BR_CHECK" ]] || break
done

gh api -X PUT /repos/FortinetCloudCSE/$REPO_NAME/branches/main/protection \
   --input - <<< '{
  "required_status_checks": {
    "strict": true,
    "contexts": [
       "ci/jenkins/build-status"
    ]
  },
  "enforce_admins": false,
  "restrictions": null,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": true,
    "required_approving_review_count": 1
  },
  "allow_force_pushes": true
}'
[[ "$?" == "0" ]] || echo "Error adding branch protections..."

# Create github webhook for jenkins builds
gh api /repos/FortinetCloudCSE/$REPO_NAME/hooks \
   --input - <<< '{
  "name": "web",
  "active": true,
  "events": [
    "push"
  ],
  "config": {
    "url": "http://jenkins.fortinetcloudcse.com:8080/github-webhook/",
    "content_type": "json"
  }
}'
[[ "$?" == "0" ]] || echo "Error creating webhook..."

# Create job in Jenkins
sed "s/REPO_NAME/$REPO_NAME/g" $JCONF > config.xml
java -jar ~/jenkins-cli.jar -s http://jenkins.fortinetcloudcse.com:8080/ -auth $JENKINS_USER_ID:$(cat ~/.jenkins-cli) create-job $REPO_NAME < config.xml
[[ "$?" == "0" ]] || echo "Error creating Jenkins pipeline..."

# Run initial manual build of repo in Jenkins
java -jar ~/jenkins-cli.jar -s http://jenkins.fortinetcloudcse.com:8080/ -auth $JENKINS_USER_ID:$(cat ~/.jenkins-cli) build $REPO_NAME
[[ "$?" == "0" ]] || echo "Error triggering first pipeline build..."
