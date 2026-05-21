#!/bin/bash

set -e

echo "BASE_BRANCH: $BASE_BRANCH"

git fetch origin $BASE_BRANCH

FILES=$(git diff --name-only origin/$BASE_BRANCH...HEAD | grep "\.swift$" || true)

if [ -z "$FILES" ]; then
  echo "No Swift files changed"
  exit 0
fi

echo "Changed files:"
echo "$FILES"

FAILED=0

for file in $FILES
do
  if [ -f "$file" ]; then
    echo "Linting: $file"
    swiftlint lint --path "$file" || FAILED=1
  fi
done

if [ $FAILED -ne 0 ]; then
  echo "SwiftLint failed"
fi

exit $FAILED