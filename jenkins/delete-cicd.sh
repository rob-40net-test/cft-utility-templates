#!/bin/bash
#
# Script to remove a FortinetCloudCSE repo and it's associated Jenkins pipeline.
# Usage: 
# delete-cicd.sh <Jenkins userid> <name of repository/pipeline>

CL_ARR=($@)

[[ " ${CL_ARR[*]} " =~ " -h " ]] && echo "Usage: ./delete-cicd.sh <Jenkins userid> <name of repository/pipeline>" && exit 0

[[ "${#CL_ARR[@]}" -ne 2 ]] && \
  echo "Usage: ./delete-cicd.sh <Jenkins userid> <name of repository/pipeline>" && \
  exit 0

JENKINS_USER_ID=${CL_ARR[0]}
REPO_NAME=${CL_ARR[1]}

# Delete Jenkins job
echo "Deleting job..."
java -jar ~/jenkins-cli.jar -s https://jenkins.fortinetcloudcse.com:8443/ -auth $JENKINS_USER_ID:$(cat ~/.jenkins-cli) delete-job $REPO_NAME
[[ "$?" == "0" ]] && echo "Deleted Jenkins job $REPO_NAME" || echo "Error deleting Jenkins pipeline..."

# Delete FortiDevSec Application
echo "Deleting FortiDevSec Application..."
TOKEN=$(cat ~/fds-token.txt)
ORG_ID=$(curl -X GET "https://fortidevsec.forticloud.com/api/v1/dashboard/get_orgs" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" | jq '.[0].id')

APP_ID=$(curl -X GET "https://fortidevsec.forticloud.com/api/v1/dashboard/get_apps?org_id=$ORG_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" | jq --arg app_name "$REPO_NAME" '.apps[] | select(.name == $app_name) | .id')

APP_UUID=$(curl -X GET "https://fortidevsec.forticloud.com/api/v1/dashboard/get_apps?org_id=$ORG_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" | jq --arg app_name "$REPO_NAME" '.apps[] | select(.name == $app_name) | .app_uuid')

echo "UUID: $APP_UUID"

STATUS=$(curl -X PUT "https://fortidevsec.forticloud.com/api/v1/dashboard/update_app" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":'"$REPO_NAME"',"app_uuid":'"$APP_UUID"',"active_status":"deactivated"}' | jq '.active_status')

echo "Status: $STATUS"

[[ "$STATUS" == "deactivated" ]] && echo "App successfully deactivated. Deleting..."

curl -X POST "https://fortidevsec.forticloud.com/api/v1/dashboard/delete_app?app_id=$APP_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json"

# Delete github repo
echo "Deleting repo..."
gh repo delete FortinetCloudCSE/$REPO_NAME
[[ "$?" == "0" ]] || echo "Error deleting repo..."
