#!/bin/bash -
#
# Script for setting up github repo and (optionally) an accompanying jenkins pipeline.
#
# Usage: 
# setup-cicd.sh [-t repo] [-j userid] [-f template-config.xml] [-c username1 -c username2 ... ] <name of new repo>
#   -t Name of template repository
#   -j Jenkins userid
#   -f Jenkins pipeline configuration xml file (if unset the default config file will be used)
#   -c GitHub username of collaborator to add

while getopts 't:j:c:hf:' opt; do
  case "${opt}" in
    t)
      USE_TEMPLATE=1 
      TEMPLATE_REPO_NAME="$OPTARG"
      ;;
    j)
      JENKINS_PIPE=1
      JENKINS_USER_ID="$OPTARG"
      ;;
    c)
      COLLABS+=("$OPTARG")
      ;;
    f)
      USER_SUPPLIED_JCONF=1
      JCONF="$OPTARG"
      ;;
    h)
      echo "Usage: setup-cicd.sh [-t repo] [-j userid] [-f template-config.xml] [-c username1 -c username2 ... ] <name of new repo>"
      echo "-t Name of template repository"
      echo "-j Jenkins userid"
      echo "-f Jenkins pipeline configuration xml file (if unset the default config file will be used)"
      echo "-c GitHub username of collaborator to add"
      exit 0
      ;;
    *)
      echo "Unknown arguments. For help run: setup-cicd.sh -h" 
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))

JCONF=${JCONF:-"template-config.xml"}
REPO_NAME=$1

[[ $REPO_NAME ]] || { echo "Error: please specify a name for the new repository."; exit 0; }

################ Create Repo
[[ $USE_TEMPLATE == 1 ]] && \
  gh repo create "FortinetCloudCSE/$REPO_NAME" -p "FortinetCloudCSE/$TEMPLATE_REPO_NAME" --public || \
  gh repo create "FortinetCloudCSE/$REPO_NAME" --public --add-readme
[[ "$?" == "0" ]] || { echo "Error creating repository, exiting script..."; exit 1; }


while : ; do
  BR_CHECK=$(gh api "/repos/FortinetCloudCSE/$REPO_NAME/branches" | jq -r '.[] | select(.name=="main")')
  [[ -z "$BR_CHECK" ]] || break
done

################ Set up branch protections
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

################ Enable pages
gh api -X POST "/repos/FortinetCloudCSE/$REPO_NAME/pages" \
   --input - <<< '{
   "build_type":"workflow",
   "source":{
     "branch":"main",
     "path":"/docs"
   }
}'
[[ "$?" == "0" ]] && echo "****GitHub Pages URL: https://fortinetcloudcse.github.io/$REPO_NAME" || \
  echo "Error enabling GitHub Pages..."

################ Add colaborators
for collab in "${COLLABS[@]}"
do 
  gh api -X PUT "repos/FortinetCloudCSE/$REPO_NAME/collaborators/$collab"
  [[ "$?" == "0" ]] || echo "Error adding $collab as collaborator..."
done

if [[ $JENKINS_PIPE == 1 ]]; then

  ############## Create github webhook for jenkins builds
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

  ############## Create job in Jenkins
  if [[ $USER_SUPPLIED_JCONF == 1 ]]; then 
    cat $JCONF > config.xml
  else
    sed "s/REPO_NAME/$REPO_NAME/g" $JCONF > config.xml
  fi
  java -jar ~/jenkins-cli.jar -s https://jenkins.fortinetcloudcse.com:8443/ -auth $JENKINS_USER_ID:$(cat ~/.jenkins-cli) create-job "$REPO_NAME" < config.xml
  [[ "$?" == "0" ]] || echo "Error creating Jenkins pipeline..."
  
  ############## Run initial manual build of repo in Jenkins
  java -jar ~/jenkins-cli.jar -s https://jenkins.fortinetcloudcse.com:8443/ -auth $JENKINS_USER_ID:$(cat ~/.jenkins-cli) build "$REPO_NAME"
  [[ "$?" == "0" ]] || echo "Error triggering first pipeline build..."
  
  echo "Create FortiDevSec app and paste app id into fdevsec.yaml."

fi
