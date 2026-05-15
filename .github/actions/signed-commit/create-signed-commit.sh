#!/usr/bin/env bash
# Create a commit with a verified signature via the GitHub Git Data API.
#
# Usage: create-signed-commit.sh REPO BRANCH COMMIT_MESSAGE [BASE_REF]
#
# Must be run from a working directory with unstaged changes.
# Requires GH_TOKEN in the environment and gh + jq on PATH.
# Prints the new commit SHA to stdout.

set -euo pipefail

REPO="$1"
BRANCH="$2"
COMMIT_MESSAGE="$3"
BASE_REF="${4:-main}"

BASE_SHA=$(gh api "/repos/${REPO}/git/ref/heads/${BASE_REF}" --jq '.object.sha')
BASE_TREE=$(gh api "/repos/${REPO}/git/commits/${BASE_SHA}" --jq '.tree.sha')

TREE_ENTRIES="[]"
for file in $(git diff --name-only); do
  BLOB_SHA=$(gh api "/repos/${REPO}/git/blobs" \
    -f content="$(base64 -w 0 "$file")" \
    -f encoding="base64" \
    --jq '.sha')
  TREE_ENTRIES=$(echo "$TREE_ENTRIES" | jq \
    --arg path "$file" \
    --arg sha "$BLOB_SHA" \
    '. + [{"path": $path, "mode": "100644", "type": "blob", "sha": $sha}]')
done

NEW_TREE=$(echo "{}" | jq \
  --arg base "$BASE_TREE" \
  --argjson tree "$TREE_ENTRIES" \
  '{base_tree: $base, tree: $tree}' \
  | gh api "/repos/${REPO}/git/trees" --input - --jq '.sha')

NEW_COMMIT=$(jq -n \
  --arg message "$COMMIT_MESSAGE" \
  --arg tree "$NEW_TREE" \
  --arg parent "$BASE_SHA" \
  '{message: $message, tree: $tree, parents: [$parent]}' \
  | gh api "/repos/${REPO}/git/commits" --input - --jq '.sha')

gh api "/repos/${REPO}/git/refs" \
  --input <(jq -n \
    --arg ref "refs/heads/${BRANCH}" \
    --arg sha "$NEW_COMMIT" \
    '{ref: $ref, sha: $sha}')

echo "$NEW_COMMIT"
