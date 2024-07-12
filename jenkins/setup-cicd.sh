#!/bin/bash -
#
# Script for setting up github repo and (optionally) an accompanying jenkins pipeline.
#
# Usage: 
# setup-cicd.sh [-t repo] [-r] [-b] [-s] [-j userid] [-f template-config.xml] [-c username1 -c username2 ... ] <name of new repo>
#   -t Name of template repository
#   -r Update README with Workshop Pages link
#   -b Apply branch protections
#   -j Jenkins userid
#   -s Setup FortiSevSec application
#   -f Jenkins pipeline configuration xml file (if unset the default config file will be used)
#   -c GitHub username of collaborator to add
#
# Note: This script assumes:
#    * The Jenkins CLI is installed at ~/jenkins-cli.jar
#    * A Jenkins personal access token is installed at ~/.jenkins-cli. The file should only contain the token on the first line of the file and nothing else.
#    * A FortiDevSec API token is installed at ~/fds-token.txt. The file should only contain the token on the first line of the file and nothing else.


while getopts 't:j:c:hf:srb' opt; do
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
    r)
      UPDATE_README=1
      ;;
    s)
      SETUP_FDS=1
      ;;
    b)
      APPLY_BR_PROT=1
      ;;
    h)
      echo "Usage: setup-cicd.sh [-t repo] [-r] [-s] [-b] [-j userid] [-f template-config.xml] [-c username1 -c username2 ... ] <name of new repo>"
      echo "-t Name of template repository"
      echo "-r Update README with Workshop Pages link"
      echo "-b Apply branch protections"
      echo "-j Jenkins userid"
      echo "-f Jenkins pipeline configuration xml file (if unset the default config file will be used)"
      echo "-s Setup FortiDevSec application"
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
TREE_FIELDS=()

update_tree_array () {
  FILENAME=$1
  OLD_STRING=$2
  NEW_STRING=$3
  RESPONSE=$(gh api /repos/FortinetCloudCSE/$REPO_NAME/contents/$FILENAME)
  CONTENT=$(echo "$RESPONSE" | jq -r '.content' | base64 --decode)
  UPDATED_CONTENT=$(echo "$CONTENT" | sed 's/'"$OLD_STRING"'/'"$NEW_STRING"'/g')
  BLOB_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/blobs \
    --method POST \
    -f content="$UPDATED_CONTENT" \
    -f encoding="utf-8" \
    -q '.sha') 
  TREE_FIELDS+=("-f \"tree[][path]=$FILENAME\"")
  TREE_FIELDS+=("-f \"tree[][mode]=100644\"")
  TREE_FIELDS+=("-f \"tree[][type]=blob\"")
  TREE_FIELDS+=("-f \"tree[][sha]=$BLOB_SHA\"")
}

[[ $REPO_NAME ]] || { echo "Error: please specify a name for the new repository."; exit 0; }

################ Create Repo
[[ "$USE_TEMPLATE" == "1" ]] && \
  gh repo create "FortinetCloudCSE/$REPO_NAME" -p "FortinetCloudCSE/$TEMPLATE_REPO_NAME" --public || \
  gh repo create "FortinetCloudCSE/$REPO_NAME" --public --add-readme
[[ "$?" == "0" ]] || { echo "Error creating repository, exiting script..."; exit 1; }


while : ; do
  BR_CHECK=$(gh api "/repos/FortinetCloudCSE/$REPO_NAME/branches" | jq -r '.[] | select(.name=="main")')
  [[ -z "$BR_CHECK" ]] || break
done

## Get current commit SHA and current tree SHA for ensuing steps
CURRENT_COMMIT_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/branches/main -q '.commit.sha')
BASE_TREE_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/commits/$CURRENT_COMMIT_SHA -q '.tree.sha')

################ Set up branch protections
if [[ "$APPLY_BR_PROT" ]]; then 
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

## Update README with GH Pages link
if [[ "$UPDATE_README" == "1" ]]; then
  PG_URL=$(gh api -X GET -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      /repos/FortinetCloudCSE/$REPO_NAME/pages | jq -r '.html_url')
  README_CONTENT="<h1>$REPO_NAME</h1><h3>To view the workshop, please go here: <a href="$PG_URL">$REPO_NAME</a></h3><hr><h3>For more information on creating these workshops, please go here: <a href="https://fortinetcloudcse.github.io/UserRepo/">FortinetCloudCSE User Repo</a></h3>"
  BLOB_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/blobs \
    --method POST \
    -f content="$README_CONTENT" \
    -f encoding="utf-8" \
    -q '.sha')
  TREE_FIELDS+=("-f \"tree[][path]=README.md\"")
  TREE_FIELDS+=("-f \"tree[][mode]=100644\"")
  TREE_FIELDS+=("-f \"tree[][type]=blob\"")
  TREE_FIELDS+=("-f \"tree[][sha]=$BLOB_SHA\"")
fi

################ FortiDevSec Setup
if [[ "$SETUP_FDS" == "1" ]]; then
   TOKEN=$(cat ~/fds-token.txt)
   
   ORG_ID=$(curl -X GET "https://fortidevsec.forticloud.com/api/v1/dashboard/get_orgs" \
       -H "Authorization: Bearer $TOKEN" \
       -H "Content-Type: application/json" | jq '.[0].id')
   
   FDS_APP_ID=$(curl -X POST "https://fortidevsec.forticloud.com/api/v1/dashboard/create_app?org_id=$ORG_ID&app_name=$REPO_NAME" \
       -H "Authorization: Bearer $TOKEN" \
       -H "Content-Type: application/json" | jq -r '.app_uuid')

   update_tree_array "fdevsec.yaml" "<insert app id here>" "$FDS_APP_ID"
fi
[[ "$?" == "0" ]] && echo "FortiDevSec application setup successfully."


################ Add colaborators
for collab in "${COLLABS[@]}"
do 
  gh api -X PUT "repos/FortinetCloudCSE/$REPO_NAME/collaborators/$collab"
  [[ "$?" == "0" ]] || echo "Error adding $collab as collaborator..."
done

################ Jenkins setup
if [[ "$JENKINS_PIPE" == "1" ]]; then

  update_tree_array "Jenkinsfile" "when { expression { false } }" "when { expression { true } }"

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
  if [[ "$USER_SUPPLIED_JCONF" == "1" ]]; then 
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

################ Create Git tree with updated files
if [[ "${#TREE_FIELDS[@]}" > 0 ]]; then
  NEW_TREE_SHA=$(eval "gh api /repos/FortinetCloudCSE/$REPO_NAME/git/trees \
    --method POST \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -f 'base_tree=$BASE_TREE_SHA' ${TREE_FIELDS[@]} \
    -q '.sha'")
  
  COMMIT_MESSAGE="Initial repo setup."
  NEW_COMMIT_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/commits \
    --method POST \
    -f "message=$COMMIT_MESSAGE" \
    -f "tree=$NEW_TREE_SHA" \
    -f "parents[]=$CURRENT_COMMIT_SHA" \
    -q ".sha")
  
  gh api repos/FortinetCloudCSE/$REPO_NAME/git/refs/heads/main \
    --method PATCH \
    -f sha="$NEW_COMMIT_SHA"
fi
