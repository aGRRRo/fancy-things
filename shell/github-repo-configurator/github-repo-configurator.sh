#!/bin/bash

# Disable gh pager for non-interactive mode
export GH_PAGER=''

# Check dependencies
command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI is required. Install from https://cli.github.com/"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required. Install from https://stedolan.github.io/jq/"; exit 1; }

# Arguments
ORG="$1"
JSON_INPUT="$2"

if [ -z "$ORG" ] || [ -z "$JSON_INPUT" ]; then
  echo "Usage: $0 <ORG_NAME> <JSON_FILE_PATH> (use '-' for stdin)"
  exit 1
fi

# Read JSON from file or stdin
if [ "$JSON_INPUT" = "-" ]; then
  JSON_DATA=$(cat)
else
  JSON_DATA=$(cat "$JSON_INPUT")
fi

# Validate JSON (basic structure)
echo "$JSON_DATA" | jq . >/dev/null 2>&1 || { echo "Error: Invalid JSON payload (syntax error)"; exit 1; }

# Enhanced check: Ensure "repositories" is an array
REPOS_TYPE=$(echo "$JSON_DATA" | jq 'if has("repositories") then .repositories | type else "null" end')
if [ "$REPOS_TYPE" != '"array"' ]; then
  echo "Error: 'repositories' must be a non-null array in JSON. Found type: $REPOS_TYPE. Fix your JSON and retry."
  exit 1
fi

# Function to create repo if it doesn't exist (no --default-branch for compatibility with gh 2.24.3)
create_repo_if_not_exists() {
  local repo="$1"
  local visibility="$2"

  if gh repo view "$ORG/$repo" --json name >/dev/null 2>&1; then
    echo "Repository $ORG/$repo already exists. Skipping creation."
    return 0
  fi

  echo "Creating repository $ORG/$repo with visibility '$visibility' (initial branch 'main')..."
  gh repo create "$ORG/$repo" --"$visibility" || { echo "Error creating $repo"; return 1; }
  echo "Repository $repo created."
  return 0
}

# Function to initialize main with a dummy commit (for new repos)
initialize_main_branch() {
  local repo="$1"

  echo "Initializing 'main' branch with dummy commit in $ORG/$repo..."
  local content=$(echo "Initial commit" | base64)
  gh api --method PUT -H "Accept: application/vnd.github.v3+json" "/repos/$ORG/$repo/contents/README.md" \
    -f "message=Initial commit on main" \
    -f "content=$content" \
    -f "branch=main" || { echo "Error initializing 'main' in $repo"; return 1; }
  echo "'main' initialized."
}

# Function to set default branch (creates it if needed from main)
set_default_branch() {
  local repo="$1"
  local target_branch="$2"

  if [ "$target_branch" = "main" ] || [ -z "$target_branch" ]; then
    echo "Default branch is already 'main' or not specified for $ORG/$repo. Skipping."
    return 0
  fi

  # Create the target branch from main if it doesn't exist
  create_branch_if_not_exists "$repo" "$target_branch" "main" || return 1

  # Set as default
  echo "Switching default branch to '$target_branch' in $ORG/$repo..."
  gh api --method PATCH -H "Accept: application/vnd.github.v3+json" "/repos/$ORG/$repo" \
    -f "default_branch=$target_branch" || { echo "Error switching default branch"; return 1; }
  echo "Default branch switched to '$target_branch'."
}

# Function to update general repo settings
update_repo_settings() {
  local repo="$1"
  local suggest_update="${2:-true}"
  local auto_delete="${3:-true}"
  local allow_forking="${4:-false}"

  echo "Updating general settings for $ORG/$repo..."
  gh api --method PATCH -H "Accept: application/vnd.github.v3+json" "/repos/$ORG/$repo" \
    -F "allow_update_branch=$suggest_update" \
    -F "delete_branch_on_merge=$auto_delete" \
    -F "allow_forking=$allow_forking" || { echo "Error updating settings for $repo"; return 1; }
  echo "Settings updated."
}

# Function to add CODEOWNERS file if not exists (in root on 'main') - Enhanced with verification
add_codeowners() {
  local repo="$1"
  local content="${2:-* @TEST/test-reviewers}"  # Default content

  if [ -z "$content" ]; then
    echo "Warning: No content provided for CODEOWNERS in $ORG/$repo. Skipping."
    return 0
  fi

  local branch="main"

  # Check if file exists on main
  if gh api "/repos/$ORG/$repo/contents/CODEOWNERS?ref=$branch" >/dev/null 2>&1; then
    echo "CODEOWNERS already exists on '$branch' in $ORG/$repo. Skipping addition."
    return 0
  else
    echo "CODEOWNERS does not exist on '$branch' in $ORG/$repo. Proceeding to add."
  fi

  echo "Adding/Updating CODEOWNERS to root of $ORG/$repo on '$branch'..."
  local encoded_content=$(echo -e "$content" | base64)
  gh api --method PUT -H "Accept: application/vnd.github.v3+json" "/repos/$ORG/$repo/contents/CODEOWNERS" \
    -f "message=Add or update CODEOWNERS file" \
    -f "content=$encoded_content" \
    -f "branch=$branch" || { echo "Error: Failed to add/update CODEOWNERS to $repo on '$branch'"; return 1; }

  # Verify addition
  sleep 1  # Brief delay for API consistency
  if gh api "/repos/$ORG/$repo/contents/CODEOWNERS?ref=$branch" >/dev/null 2>&1; then
    echo "CODEOWNERS successfully added/updated and verified on '$branch'."
  else
    echo "Error: CODEOWNERS addition failed verification on '$branch' in $ORG/$repo."
    return 1
  fi
}

# Function to create a branch if it doesn't exist (updated with base parameter)
create_branch_if_not_exists() {
  local repo="$1"
  local branch="$2"
  local base="${3:-main}"  # Default base is main

  if gh api "/repos/$ORG/$repo/branches/$branch" >/dev/null 2>&1; then
    echo "Branch '$branch' already exists in $ORG/$repo."
    return 0
  fi

  echo "Creating branch '$branch' in $ORG/$repo from '$base'..."
  local base_sha=$(gh api "/repos/$ORG/$repo/branches/$base" --jq '.commit.sha')
  if [ -z "$base_sha" ]; then
    echo "Error: Base branch '$base' has no commits in $repo"
    return 1
  fi
  gh api --method POST -H "Accept: application/vnd.github.v3+json" "/repos/$ORG/$repo/git/refs" \
    -f "ref=refs/heads/$branch" \
    -f "sha=$base_sha" || { echo "Error creating branch $branch"; return 1; }
  echo "Branch '$branch' created."
}

# Function to apply branch protection (per branch) - Fixed with proper JSON payload
apply_branch_protection() {
  local repo="$1"
  local branch="$2"
  local required_approvals="${3:-2}"
  local require_code_owner_reviews="${4:-true}"
  local dismiss_stale_reviews="${5:-true}"
  local enforce_admins="${6:-false}"

  create_branch_if_not_exists "$repo" "$branch" || return 1

  echo "Applying classic branch protection to '$branch' in $ORG/$repo (approvals: $required_approvals, code owners: $require_code_owner_reviews, dismiss stale: $dismiss_stale_reviews, enforce admins: $enforce_admins)..."

  # Use JSON payload with correct types (booleans without quotes, integer for count)
  gh api --method PUT -H "Accept: application/vnd.github+json" "/repos/$ORG/$repo/branches/$branch/protection" \
    --input - <<EOF || { echo "Error applying protection to $branch (check API response)"; return 1; }
{
  "required_status_checks": null,
  "enforce_admins": $enforce_admins,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": $dismiss_stale_reviews,
    "require_code_owner_reviews": $require_code_owner_reviews,
    "required_approving_review_count": $required_approvals
  },
  "restrictions": null
}
EOF
  echo "Protection applied to '$branch'."
}

# Function to set autolinks - Updated with check for existing
set_autolinks() {
  local repo="$1"
  local autolinks="$2"

  # Fetch existing autolinks
  local existing_autolinks=$(gh api "/repos/$ORG/$repo/autolinks" --paginate || echo "[]")

  local autolink_count=$(echo "$autolinks" | jq 'if type == "array" then length else 0 end')
  for j in $(seq 0 $(($autolink_count - 1))); do
    local key_prefix=$(echo "$autolinks" | jq -r ".[$j].key_prefix // empty")
    local url_template=$(echo "$autolinks" | jq -r ".[$j].url_template // empty")
    local is_alphanumeric=$(echo "$autolinks" | jq -r ".[$j].is_alphanumeric // true")

    if [ -z "$key_prefix" ] || [ -z "$url_template" ]; then
      echo "Warning: Skipping invalid autolink entry"
      continue
    fi

    # Check if this autolink already exists (match by key_prefix and url_template)
    local exists=$(echo "$existing_autolinks" | jq --arg kp "$key_prefix" --arg ut "$url_template" '[.[] | select(.key_prefix == $kp and .url_template == $ut)] | length > 0')

    if [ "$exists" = "true" ]; then
      echo "Autolink for $key_prefix already configured in $ORG/$repo. Skipping."
      continue
    fi

    echo "Setting autolink: $key_prefix -> $url_template"
    gh api --method POST "/repos/$ORG/$repo/autolinks" \
      -f "key_prefix=$key_prefix" \
      -f "url_template=$url_template" \
      -F "is_alphanumeric=$is_alphanumeric" || echo "Error setting autolink"
  done
}

# Function to add collaborators
set_collaborators() {
  local repo="$1"
  local collaborators="$2"

  local collab_count=$(echo "$collaborators" | jq 'if type == "array" then length else 0 end')
  for j in $(seq 0 $(($collab_count - 1))); do
    local username=$(echo "$collaborators" | jq -r ".[$j].username // empty")
    local permission=$(echo "$collaborators" | jq -r ".[$j].permission // empty")

    if [ -z "$username" ] || [ -z "$permission" ]; then
      echo "Warning: Skipping invalid collaborator entry"
      continue
    fi

    echo "Adding collaborator $username with $permission"
    gh api --method PUT "/repos/$ORG/$repo/collaborators/$username" -f "permission=$permission" || echo "Error adding $username"
  done
}

# Function to add teams (updated to parse slug)
set_teams() {
  local repo="$1"
  local teams="$2"

  local team_count=$(echo "$teams" | jq 'if type == "array" then length else 0 end')
  for j in $(seq 0 $(($team_count - 1))); do
    local full_slug=$(echo "$teams" | jq -r ".[$j].slug // empty")
    local permission=$(echo "$teams" | jq -r ".[$j].permission // empty")

    if [ -z "$full_slug" ] || [ -z "$permission" ]; then
      echo "Warning: Skipping invalid team entry"
      continue
    fi

    # Parse slug: strip @org/ prefix and lowercase
    local parsed_slug=$(echo "$full_slug" | sed 's/^@[^/]*\///' | tr '[:upper:]' '[:lower:]')

    echo "Adding team $parsed_slug with $permission"
    gh api --method PUT "/orgs/$ORG/teams/$parsed_slug/repos/$ORG/$repo" -f "permission=$permission" || echo "Error adding $parsed_slug (check if slug '$parsed_slug' exists)"
  done
}

# Function to set repo-level actions/dependabot - With retry for public-key fetch
set_repo_level_config() {
  local repo="$1"
  local actions_vars="$2"
  local actions_secrets="$3"
  local dependabot_secrets="$4"

  # Helper function to set secret with retry
  set_secret_with_retry() {
    local key="$1"
    local value="$2"
    local app="$3"  # actions or dependabot
    local max_retries=3
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
      gh secret set "$key" --app "$app" --repo "$ORG/$repo" --body "$value" && return 0
      echo "Warning: Failed to set secret $key (attempt $((retry_count+1))). Retrying in 5 seconds..."
      sleep 5
      retry_count=$((retry_count+1))
    done
    echo "Error: Failed to set secret $key after $max_retries attempts."
    return 1
  }

  echo "Setting Actions variables for $ORG/$repo..."
  echo "$actions_vars" | jq -r 'if type == "object" then to_entries[] | "\(.key) \(.value)" else empty end' | while read -r key value; do
    echo "Setting variable $key"
    gh variable set "$key" --repo "$ORG/$repo" --body "$value" || echo "Error setting variable $key"
  done

  echo "Setting Actions secrets for $ORG/$repo..."
  echo "$actions_secrets" | jq -r 'if type == "object" then to_entries[] | "\(.key) \(.value)" else empty end' | while read -r key value; do
    echo "Setting secret $key"
    set_secret_with_retry "$key" "$value" "actions" || echo "Error setting secret $key"
  done

  echo "Setting Dependabot secrets for $ORG/$repo..."
  echo "$dependabot_secrets" | jq -r 'if type == "object" then to_entries[] | "\(.key) \(.value)" else empty end' | while read -r key value; do
    echo "Setting secret $key"
    set_secret_with_retry "$key" "$value" "dependabot" || echo "Error setting secret $key"
  done
}

# Function to apply shared configs (updated with robust checks)
apply_shared_configs() {
  # Shared Actions variables
  local shared_actions_vars=$(echo "$JSON_DATA" | jq -c '.shared.actions.variables // []')
  local shared_actions_vars_count=$(echo "$shared_actions_vars" | jq 'if type == "array" then length else 0 end')
  for i in $(seq 0 $(($shared_actions_vars_count - 1))); do
    local name=$(echo "$shared_actions_vars" | jq -r ".[$i].name // empty")
    local value=$(echo "$shared_actions_vars" | jq -r ".[$i].value // empty")
    local repos=$(echo "$shared_actions_vars" | jq -c ".[$i].repos // []" | jq -r '.[] // empty')

    if [ -z "$name" ] || [ -z "$value" ]; then
      echo "Warning: Skipping absent/undefined shared Actions variable entry"
      continue
    fi

    for repo in $repos; do
      echo "Setting shared Actions var $name in $ORG/$repo"
      gh variable set "$name" --repo "$ORG/$repo" --body "$value" || echo "Error setting $name in $repo"
    done
  done

  # Shared Actions secrets (similar)
  local shared_actions_secrets=$(echo "$JSON_DATA" | jq -c '.shared.actions.secrets // []')
  local shared_actions_secrets_count=$(echo "$shared_actions_secrets" | jq 'if type == "array" then length else 0 end')
  for i in $(seq 0 $(($shared_actions_secrets_count - 1))); do
    local name=$(echo "$shared_actions_secrets" | jq -r ".[$i].name // empty")
    local value=$(echo "$shared_actions_secrets" | jq -r ".[$i].value // empty")
    local repos=$(echo "$shared_actions_secrets" | jq -c ".[$i].repos // []" | jq -r '.[] // empty')

    if [ -z "$name" ] || [ -z "$value" ]; then
      echo "Warning: Skipping absent/undefined shared Actions secret entry"
      continue
    fi

    for repo in $repos; do
      echo "Setting shared Actions secret $name in $ORG/$repo"
      gh secret set "$name" --app actions --repo "$ORG/$repo" --body "$value" || echo "Error setting $name in $repo"
    done
  done

  # Shared Dependabot secrets (similar)
  local shared_dependabot_secrets=$(echo "$JSON_DATA" | jq -c '.shared.dependabot.secrets // []')
  local shared_dependabot_secrets_count=$(echo "$shared_dependabot_secrets" | jq 'if type == "array" then length else 0 end')
  for i in $(seq 0 $(($shared_dependabot_secrets_count - 1))); do
    local name=$(echo "$shared_dependabot_secrets" | jq -r ".[$i].name // empty")
    local value=$(echo "$shared_dependabot_secrets" | jq -r ".[$i].value // empty")
    local repos=$(echo "$shared_dependabot_secrets" | jq -c ".[$i].repos // []" | jq -r '.[] // empty')

    if [ -z "$name" ] || [ -z "$value" ]; then
      echo "Warning: Skipping absent/undefined shared Dependabot secret entry"
      continue
    fi

    for repo in $repos; do
      echo "Setting shared Dependabot secret $name in $ORG/$repo"
      gh secret set "$name" --app dependabot --repo "$ORG/$repo" --body "$value" || echo "Error setting $name in $repo"
    done
  done

  if echo "$JSON_DATA" | jq '.shared.dependabot.variables // empty' | grep -q .; then
    echo "Warning: Dependabot does not support variables. Skipping."
  fi
}

# Function to process all repositories (main loop wrapped here to allow local vars)
process_repositories() {
  local repo_count=$(echo "$JSON_DATA" | jq '.repositories | if type == "array" then length else 0 end')
  if [ "$repo_count" -eq 0 ]; then
    echo "Warning: No valid repositories found in JSON. Nothing to process."
    return
  fi

  for i in $(seq 0 $(($repo_count - 1))); do
    local repo_name=$(echo "$JSON_DATA" | jq -r ".repositories[$i].name // empty")
    local visibility=$(echo "$JSON_DATA" | jq -r ".repositories[$i].visibility // \"private\"")
    local default_branch=$(echo "$JSON_DATA" | jq -r ".repositories[$i].default_branch // \"\"")
    local suggest_update=$(echo "$JSON_DATA" | jq -r ".repositories[$i].settings.suggest_update_branch // true")
    local auto_delete=$(echo "$JSON_DATA" | jq -r ".repositories[$i].settings.auto_delete_head // true")
    local allow_forking=$(echo "$JSON_DATA" | jq -r ".repositories[$i].settings.allow_forking // false")
    local add_codeowners=$(echo "$JSON_DATA" | jq -r ".repositories[$i].add_codeowners // true")
    local codeowners_content=$(echo "$JSON_DATA" | jq -r ".repositories[$i].codeowners_content // \"* @TEST/test-reviewers\"")
    local actions_vars=$(echo "$JSON_DATA" | jq -c ".repositories[$i].actions.variables // {}")
    local actions_secrets=$(echo "$JSON_DATA" | jq -c ".repositories[$i].actions.secrets // {}")
    local dependabot_secrets=$(echo "$JSON_DATA" | jq -c ".repositories[$i].dependabot.secrets // {}")
    local autolinks=$(echo "$JSON_DATA" | jq -c ".repositories[$i].autolinks // []")
    local collaborators=$(echo "$JSON_DATA" | jq -c ".repositories[$i].collaborators // []")
    local teams=$(echo "$JSON_DATA" | jq -c ".repositories[$i].teams // []")
    local branch_protections=$(echo "$JSON_DATA" | jq -c 'if .repositories['$i'].branch_protection then .repositories['$i'].branch_protection else [ {"branch": "main", "required_approvals": 2, "require_code_owner_reviews": true, "dismiss_stale_reviews": true, "enforce_admins": false}, {"branch": "develop", "required_approvals": 2, "require_code_owner_reviews": true, "dismiss_stale_reviews": true, "enforce_admins": false} ] end')

    if [ -z "$repo_name" ]; then
      echo "Error: Invalid repo entry at index $i (missing name). Skipping."
      continue
    fi

    echo "Processing $ORG/$repo_name"

    # Create repo and track if it's new
    local is_new_repo=0
    if ! gh repo view "$ORG/$repo_name" --json name >/dev/null 2>&1; then
      create_repo_if_not_exists "$repo_name" "$visibility" || continue
      is_new_repo=1
    fi

    # For new repos, initialize main immediately
    if [ "$is_new_repo" -eq 1 ]; then
      initialize_main_branch "$repo_name" || continue
    fi

    # Add CODEOWNERS on main (before any default switch)
    if [ "$add_codeowners" = "true" ]; then
      add_codeowners "$repo_name" "$codeowners_content" || continue
    fi

    # Set custom default branch if specified
    set_default_branch "$repo_name" "$default_branch" "$is_new_repo" || continue

    update_repo_settings "$repo_name" "$suggest_update" "$auto_delete" "$allow_forking" || continue

    # Apply branch protections
    local branch_count=$(echo "$branch_protections" | jq 'if type == "array" then length else 0 end')
    if [ "$branch_count" -eq 0 ]; then
      echo "Warning: No branch protections defined for $repo_name (fallback failed). Skipping."
    else
      for j in $(seq 0 $(($branch_count - 1))); do
        local branch=$(echo "$branch_protections" | jq -r ".[$j].branch // empty")
        local req_approvals=$(echo "$branch_protections" | jq -r ".[$j].required_approvals // 2")
        local req_code_owners=$(echo "$branch_protections" | jq -r ".[$j].require_code_owner_reviews // true")
        local dismiss_stale=$(echo "$branch_protections" | jq -r ".[$j].dismiss_stale_reviews // true")
        local enforce_admins=$(echo "$branch_protections" | jq -r ".[$j].enforce_admins // false")

        if [ -z "$branch" ]; then
          echo "Warning: Skipping invalid branch protection entry (missing branch name)"
          continue
        fi

        apply_branch_protection "$repo_name" "$branch" "$req_approvals" "$req_code_owners" "$dismiss_stale" "$enforce_admins" || continue
      done
    fi

    set_autolinks "$repo_name" "$autolinks" || continue
    set_collaborators "$repo_name" "$collaborators" || continue
    set_teams "$repo_name" "$teams" || continue

    # Moved to end: Set variables and secrets after everything else
    set_repo_level_config "$repo_name" "$actions_vars" "$actions_secrets" "$dependabot_secrets" || continue

    echo "Completed processing for $repo_name"
  done
}

# Process repositories first (creates repos)
process_repositories

# Then apply shared configs (now repos exist)
apply_shared_configs

echo "All processing completed."