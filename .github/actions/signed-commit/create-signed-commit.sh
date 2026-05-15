#!/usr/bin/env bash
# Create a commit with a verified signature using the GraphQL
# createCommitOnBranch mutation (GitHub auto-signs these commits).
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

# Get the base commit SHA
BASE_SHA=$(gh api "/repos/${REPO}/git/ref/heads/${BASE_REF}" --jq '.object.sha')

# Create the branch pointing at the base
gh api "/repos/${REPO}/git/refs" \
  --input <(jq -n \
    --arg ref "refs/heads/${BRANCH}" \
    --arg sha "$BASE_SHA" \
    '{ref: $ref, sha: $sha}')

# Build additions array from changed files
ADDITIONS="[]"
for file in $(git diff --name-only); do
  ADDITIONS=$(echo "$ADDITIONS" | jq \
    --arg path "$file" \
    --arg contents "$(base64 -w 0 "$file")" \
    '. + [{"path": $path, "contents": $contents}]')
done

# Create a signed commit via the GraphQL createCommitOnBranch mutation.
# Unlike the Git Data REST API, this mutation produces verified signatures.
QUERY='mutation($input: CreateCommitOnBranchInput!) {
  createCommitOnBranch(input: $input) {
    commit { oid }
  }
}'

COMMIT_SHA=$(jq -n \
  --arg query "$QUERY" \
  --arg repo "$REPO" \
  --arg branch "$BRANCH" \
  --arg oid "$BASE_SHA" \
  --arg message "$COMMIT_MESSAGE" \
  --argjson additions "$ADDITIONS" \
  '{
    query: $query,
    variables: {
      input: {
        branch: {
          repositoryNameWithOwner: $repo,
          branchName: $branch
        },
        message: { headline: $message },
        fileChanges: { additions: $additions },
        expectedHeadOid: $oid
      }
    }
  }' \
  | gh api -X POST /graphql --input - --jq '.data.createCommitOnBranch.commit.oid')

echo "$COMMIT_SHA"
