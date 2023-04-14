#!/bin/bash

# Script to create a repo within FortinetCloudCSE from a template repo, add a webhook to trigger Jenkins builds, 
# create a pipeline in Jenkins, and trigger a manual first build. Ensure you've downloaded the jenkins-cli.jar 
# to your home directory.

# Usage: ./setup-build-scripts.sh <Name of New Repo> <Github username of collaborator to be added>

REPO_NAME=$1
COLLAB=$2

# Create repo
gh repo create $REPO_NAME -p FortinetCloudCSE/DemoFrontEndDocker --public

# Add user to repo as COLLABorator
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
  }
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
sed "s/REPO_NAME/$REPO_NAME/g" template-config.xml > config.xml
java -jar ~/jenkins-cli.jar -s http://jenkins.fortinetcloudcse.com:8080/ -auth admin:<insert API token here> create-job $REPO_NAME < config.xml
[[ "$?" == "0" ]] || echo "Error creating Jenkins pipeline..."

# Run initial manual build of repo in Jenkins
java -jar ~/jenkins-cli.jar -s http://jenkins.fortinetcloudcse.com:8080/ -auth admin:<insert API token here> build $REPO_NAME
[[ "$?" == "0" ]] || echo "Error triggering first pipeline build..."
