#!/bin/bash
#
# Script for modifying existing GitHub repo configurations and/or creating a pipeline in Jenkins for an existing GitHub repo.
#
# Usage:
# modify-cicd.sh [-j userid] [-c username -c username ... ] [-w] [-r] [-b] [-f template-config.xml] <name of repository>
#   -j Jenkins userid; if left out only GitHub operations will be performed
#   -c usernames of collaborator to add to repo
#   -w add a Jenkins webhook to the repo
#   -r remove Main branch protections
#   -b add branch protections based on Jenkins pipeline execution status
#   -f specify a Jenkins pipeline configuration xml

while getopts 'j:c:rwbh' opt; do
  case "${opt}" in
    j)
      JENKINS_TASK=1
      JENKINS_USER_ID="$OPTARG"
      ;;
    c)
      ADD_COLLABS=1
      COLLABS+=("$OPTARG")
      ;;
    w)
      ADD_WEBHOOK=1
      ;;
    b) 
      ADD_BR_PROTECT=1
      ;;
    f)
      USER_SUPPLIED_JCONF=1
      JCONF="$OPTARG"
      ;;
    r)
      REM_PROT=1
      ;;
    h)
      echo "Usage: modify-cicd.sh [-j userid] [-c username -c username ... ] [-w] [-r] [-b] [-f template-config.xml] <name of repository>"
      echo "-j Jenkins userid; if left out only GitHub operations will be performed"
      echo "-c username of collaborator to add to repo"
      echo "-w add a Jenkins webhook to the repo"
      echo "-r remove Main branch protections"
      echo "-b add branch protections based on Jenkins pipeline execution status"
      echo "-f specify a Jenkins pipeline configuration xml"
      exit 0
      ;;
    *)
      echo "Unknown arguments. For help run: modify-cicd.sh -h"
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))    

JCONF=${JCONF:-"template-config.xml"}
REPO_NAME=$1

# Check repo exists
git ls-remote https://github.com/FortinetCloudCSE/$REPO_NAME > /dev/null
[[ "$?" == "0" ]] && echo "Branch protection rule deleted." || { "That repo doesn't exist, exiting..."; exit 1; }

# Add webhook if specified
if [[ "$ADD_WEBHOOK" == "1" ]]; then
  gh api "/repos/FortinetCloudCSE/$REPO_NAME/hooks" \
     --input - <<< '{
    "name": "web",
    "active": true,
    "events": [
      "push"
    ],
    "config": {
      "url": "https://jenkins.fortinetcloudcse.com:8443/github-webhook/",
      "content_type": "json"
    }
  }'
  [[ "$?" == "0" ]] || echo "Error creating webhook..."
fi

# Add branch protection rule if specified
if [[ "$ADD_BR_PROTECT" == "1" ]]; then
  gh api -X PUT "/repos/FortinetCloudCSE/$REPO_NAME/branches/main/protection" \
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
fi

# Delete branch protection rule
if [[ "$REM_PROT" == "1" ]]; then
  gh api \
    --method DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/FortinetCloudCSE/$REPO_NAME/branches/main/protection"
fi

# Add collaborators
if [[ "$ADD_COLLABS" == "1" ]]; then
  for collab in "${COLLABS[@]}"
    do
      gh api -X PUT repos/FortinetCloudCSE/$REPO_NAME/collaborators/$collab
      [[ "$?" == "0" ]] || echo "Error adding $collab as collaborator..."
    done
fi

# Create Jenkins pipeline if specified
if [[ "$JENKINS_TASK" == "1" ]]; then
  if [[ "$USER_SUPPLIED_JCONF" == "1" ]]; then
    cat $JCONF > config.xml
  else
    sed "s/REPO_NAME/$REPO_NAME/g" $JCONF > config.xml
  fi
  java -jar ~/jenkins-cli.jar -s https://jenkins.fortinetcloudcse.com:8443/ -auth $JENKINS_USER_ID:$(cat ~/.jenkins-cli) create-job $REPO_NAME < config.xml
  [[ "$?" == "0" ]] || echo "Error creating Jenkins pipeline..."
  
  # Run initial manual build of repo in Jenkins
  java -jar ~/jenkins-cli.jar -s https://jenkins.fortinetcloudcse.com:8443/ -auth $JENKINS_USER_ID:$(cat ~/.jenkins-cli) build $REPO_NAME
  [[ "$?" == "0" ]] || echo "Error triggering first pipeline build..."
fi
