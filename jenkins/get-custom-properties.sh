#!/bin/bash

while getopts 't:h' opt; do
  case "${opt}" in
    t)
      REPO_NAME="$OPTARG"
      ;;
    h)
      echo "Usage: get-custom-properties.sh [-t repo]"
      echo "-t Name of repository"
      exit 0
      ;;
    *)
      echo "Unknown arguments. For help run: get-custom-properties.sh -h" 
      exit 2
      ;;
  esac
done

# Check repo exists
git ls-remote https://github.com/FortinetCloudCSE/$REPO_NAME > /dev/null
[[ "$?" == "0" ]] || { "That repo wasn't found in the FortinetCloudCSE Organization, exiting..."; exit 1; }

cp_ob=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/FortinetCloudCSE/$REPO_NAME/properties/values)

cloud_provider=$(echo $cp_ob | jq '.[] | select(.property_name == "cloud-provider") | .value')
function=$(echo $cp_ob | jq '.[] | select(.property_name == "function") | .value')

echo $cloud_provider
echo $function


