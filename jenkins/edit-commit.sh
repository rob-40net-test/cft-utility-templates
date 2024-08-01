#!/bin/bash

# Usage: ./edit-commit.sh <repo-name>
# Edit the repository by adding or modifying appropriate function calls to the code block below as detailed in the examples there.

REPO_NAME=$1

if [[ -z "$REPO_NAME" ]]; then
  echo "Please supply a repository name. Usage: ./perf-commit.sh <repo-name>"
  exit 1
fi  

CURRENT_COMMIT_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/branches/main -q '.commit.sha')
BASE_TREE_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/commits/$CURRENT_COMMIT_SHA -q '.tree.sha')

TREE_FIELDS=()

update_tree_array_sed () {
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

update_tree_array_new_file () {
  FILENAME=$1
  EXT_REPO_NAME=$2
  RESPONSE=$(gh api /repos/FortinetCloudCSE/$EXT_REPO_NAME/contents/$FILENAME)
  CONTENT=$(echo "$RESPONSE" | jq -r '.content' | base64 --decode)
  BLOB_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/blobs \
    --method POST \
    -f content="$CONTENT" \
    -f encoding="utf-8" \
    -q '.sha') 
  TREE_FIELDS+=("-f \"tree[][path]=$FILENAME\"")
  TREE_FIELDS+=("-f \"tree[][mode]=100644\"")
  TREE_FIELDS+=("-f \"tree[][type]=blob\"")
  TREE_FIELDS+=("-f \"tree[][sha]=$BLOB_SHA\"")
}

add_submodule () {
  SUBMODULE_URL=$1
  SUBMODULE_PATH=$2

  git submodule add "$SUBMODULE_URL" "$SUBMODULE_PATH"
  SUBMODULE_SHA=$(cd "$SUBMODULE_PATH" && git rev-parse HEAD)

  GITMODULES_CONTENT="[submodule \"$SUBMODULE_PATH\"]\n\tpath = $SUBMODULE_PATH\n\turl = $SUBMODULE_URL"
  BLOB_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/blobs \
    --method POST \
    -f content="$GITMODULES_CONTENT" \
    -f encoding="utf-8" \
    -q '.sha') 
  
  TREE_FIELDS+=("-f \"tree[][path]=.gitmodules\"")
  TREE_FIELDS+=("-f \"tree[][mode]=100644\"")
  TREE_FIELDS+=("-f \"tree[][type]=blob\"")
  TREE_FIELDS+=("-f \"tree[][sha]=$BLOB_SHA\"")

  TREE_FIELDS+=("-f \"tree[][path]=$SUBMODULE_PATH\"")
  TREE_FIELDS+=("-f \"tree[][mode]=160000\"")
  TREE_FIELDS+=("-f \"tree[][type]=commit\"")
  TREE_FIELDS+=("-f \"tree[][sha]=$SUBMODULE_SHA\"")
}
CURRENT_COMMIT_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/branches/main -q '.commit.sha')
BASE_TREE_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/commits/$CURRENT_COMMIT_SHA -q '.tree.sha')


######### Add code here to modify files or add files from an external repo within the FortinetCloudCSE organization.

## To update/modify content of a file:
# update_tree_array_sed "filename" "text/pattern to replace" "new text"
# example: 
# update_tree_array_sed "README.md" "# Fortinet" "## Fortinet"

## To pull a file from another repo and add that file to the commit:
# update_tree_array_new_file "<file/path to file in repo>" "repo-name" 
# example: 
# update_tree_array_new_file "Dockerfile" "CentralRepo"

## To add a new submodule:
# add_submodule "<https path of repo>" "path in repo where importing"
# example: 
# add_submodule "https://github.com/McShelby/hugo-theme-relearn.git" "themes/hugo-theme-relearn"

## Edit commit message as desired.
COMMIT_MESSAGE="Update repo."

####################################################################################################################


TFL="${#TREE_FIELDS[@]}"

if [[ ! "$TFL" == "0" ]]; then

  NEW_TREE_SHA=$(eval "gh api /repos/FortinetCloudCSE/$REPO_NAME/git/trees \
      --method POST \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      -f 'base_tree=$BASE_TREE_SHA' ${TREE_FIELDS[@]} \
      -q '.sha'")
    
  NEW_COMMIT_SHA=$(gh api repos/FortinetCloudCSE/$REPO_NAME/git/commits \
      --method POST \
      -f "message=$COMMIT_MESSAGE" \
      -f "tree=$NEW_TREE_SHA" \
      -f "parents[]=$CURRENT_COMMIT_SHA" \
      -q ".sha")
    
  gh api repos/FortinetCloudCSE/$REPO_NAME/git/refs/heads/main \
      --method PATCH \
      -f sha="$NEW_COMMIT_SHA"
  
else
  echo "Nothing done. Exiting."
fi
