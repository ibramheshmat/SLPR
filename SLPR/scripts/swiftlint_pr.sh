#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="$SCRIPT_DIR/../.swiftlint.yml"

cd "$REPO_ROOT"

BASE_BRANCH="${BASE_BRANCH:-${GITHUB_BASE_REF:-main}}"
BASE_REF="${BASE_SHA:-}"

if [ -n "$BASE_REF" ] && ! git cat-file -e "$BASE_REF^{commit}" 2>/dev/null; then
  BASE_REF=""
fi

if [ -z "$BASE_REF" ]; then
  git fetch origin "$BASE_BRANCH" --quiet
  BASE_REF="origin/$BASE_BRANCH"
fi

echo "SwiftLint base: $BASE_REF"

changed_files=$(git diff --name-only --diff-filter=AMR "$BASE_REF"...HEAD -- '*.swift' || true)

if [ -z "$changed_files" ]; then
  echo "No Swift files changed in this PR"
  exit 0
fi

echo "Swift files changed in this PR:"
echo "$changed_files"

failed=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -f "$file" ] || continue

  ranges=$(
    git diff --unified=0 "$BASE_REF"...HEAD -- "$file" |
      sed -nE 's/^@@ .* \+([0-9]+)(,([0-9]+))? @@.*/\1:\3/p' |
      awk -F: '{
        count = ($2 == "" ? 1 : $2)
        if (count > 0) {
          start = $1
          end = start + count - 1
          print start ":" end
        }
      }' |
      paste -sd, -
  )

  if [ -z "$ranges" ]; then
    echo "Skipping $file because it has no added lines"
    continue
  fi

  echo "Linting added lines in: $file"

  set +e
  lint_output=$(swiftlint lint --quiet --config "$CONFIG_FILE" --reporter json "$file" 2>&1)
  lint_status=$?
  set -e

  if [ "$lint_status" -ne 0 ] && ! printf '%s' "$lint_output" | ruby -rjson -e 'JSON.parse(STDIN.read)' >/dev/null 2>&1; then
    echo "$lint_output"
    failed=1
    continue
  fi

  violations=$(
    printf '%s' "$lint_output" |
      ruby -rjson -e '
        file_path = File.expand_path(ARGV.fetch(0))
        ranges = ARGV.fetch(1).split(",").map { |range|
          start_line, end_line = range.split(":").map(&:to_i)
          (start_line..end_line)
        }

        JSON.parse(STDIN.read).each do |violation|
          violation_file = violation["file"]
          next if violation_file && File.expand_path(violation_file) != file_path

          line = violation["line"]
          next unless line && ranges.any? { |range| range.include?(line) }

          file = violation["file"]
          character = violation["character"] || 1
          severity = violation["severity"] || "warning"
          rule = violation["rule_id"] || "swiftlint"
          reason = violation["reason"] || "SwiftLint violation"

          puts "#{file}:#{line}:#{character}: #{severity}: #{rule} - #{reason}"
        end
      ' "$file" "$ranges"
  )

  if [ -n "$violations" ]; then
    echo "$violations"
    failed=1
  fi
done <<< "$changed_files"

if [ "$failed" -ne 0 ]; then
  echo "SwiftLint failed on lines added by this PR"
else
  echo "SwiftLint passed for lines added by this PR"
fi

exit "$failed"
