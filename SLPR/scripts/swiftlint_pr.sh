#!/bin/bash

set -e

echo "Current branch:"
git branch --show-current

echo "Base branch:"
echo $BASE_BRANCH

echo "Searching for changed Swift files..."

FILES=$(git diff --name-only origin/$BASE_BRANCH...HEAD | grep "\.swift$" || true)

if [ -z "$FILES" ]; then
    echo "No Swift files changed."
    exit 0
fi

echo "Changed files:"
echo "$FILES"

for file in $FILES
do
    if [ -f "$file" ]; then
        echo "Linting: $file"
        swiftlint lint --path "$file"
    fi
done