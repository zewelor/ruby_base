#!/bin/bash

# Function to display help
function display_help {
  echo "Usage: $0 [OPTION]... [NEW_NAME]"
  echo "Clone a repository, then rename 'base_projects' to a new name in file/directory names and replace 'BaseProject' string inside files."
  echo ""
  echo "Mandatory arguments:"
  echo "  new_name     new name to replace 'base_projects'"
  echo ""
  echo "Optional arguments:"
  echo "  -h, --help   display this help and exit"
}

# Check number of arguments
if [ "$#" -lt 1 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  display_help
  exit 0
fi

# Configurable constants
OLD_NAME="base_projects"

# Arguments
NEW_NAME="$1"

# Convert new_name to CamelCase using Ruby
NEW_NAME_CAMEL=$(ruby -e "puts '${NEW_NAME}'.tr('-', '_').split('_').collect(&:capitalize).join")

# Convert base name to CamelCase using Ruby
OLD_NAME_CAMEL=$(ruby -e "puts '${OLD_NAME}'.tr('-', '_').split('_').collect(&:capitalize).join")

# Function to clone repository
function clone_repository {
  git clone --depth 1 https://github.com/zewelor/ruby_base.git -b ruby-cli "${NEW_NAME}"
}

# Clone repository
clone_repository

# Directory to process
DIR_PATH="${NEW_NAME}"

# Check if the directory exists
if [ -d "$DIR_PATH" ]; then
  # Delete .git directory and reinitialize
  rm -rf "${DIR_PATH}/.git"
  cd "${DIR_PATH}"
  git init
  cd ..

  # Rename directories and files
  find "$DIR_PATH" -name "${OLD_NAME}*" | while read FILE; do
    NEW_FILE=$(echo $FILE | sed "s/${OLD_NAME}/${NEW_NAME}/g")
    mv "$FILE" "$NEW_FILE"
  done

  # Rename content inside files
  find "$DIR_PATH" -type f -exec sed -i "s/$OLD_NAME_CAMEL/$NEW_NAME_CAMEL/g" {} \;
  find "$DIR_PATH" -type f -exec sed -i "s/$OLD_NAME/$NEW_NAME/g" {} \;
else
  echo "Directory does not exist"
fi

echo "Now add new repository via https://github.com/new and push the changes to the new repository."
