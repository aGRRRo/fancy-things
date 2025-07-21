# This script provides example of GitHub repositories creation and configuration management.

## Disclaimer: Proof of Concept/Proof of Work
This script is provided "as-is" and as a Proof of Concept (POC)/(POW) and should be used at your own risk. It is intentionally designed with safety as a priority, limiting operations to adding/creating or updating configurations only—no deletions or destructive actions are performed. However, always review the script's behavior, test in a non-production environment, and verify changes to avoid unintended impacts on your repositories.

## Supported features
* General Settings -> Always suggest updating pull request branches configuration
* General Settings -> Automatically delete head branches configuration
* Allow forking configuration
* "CODEOWNERS" file with content configuration(via file creation and it's content management)
* "LICENSE" file with content configuration(via file creation and it's content management)
* Repository visibility level configuration
* Per-repository level variables and secrets for each repository for actions configuration
* Per-repository level secrets for each repository for dependabot configuration
* Shared variables and secrets for actions(for multiple repositories) configuration
* Shared secrets(multiple repos listed in json) for dependabot(for multiple repositories) configuration
* Autolink references(multiple autolinks support) configuration
* Collaborators and teams configuration( all types of roles) configuration
* Classic branch protection rules configuration(with following options:
    - Branch name pattern main and one additional branch(in case you want to change default main to another)
    - Enabled Require a pull request before merging(Require approvals =2 approvers)
    - Enabled Require review from Code Owners
    - Enabled Dismiss stale pull request approvals when new commits are pushed

## Configuration file in Json format, which supports multiple repositories creation and managment

## Pre-requisites:
* GH CLI v2.75+
* JQ 1.6+

## How-to use:
1. Edit repos-config-example.json
2. Ensure you have GH_TOKEN env variable set and your token has enough permissions
3. Run script: ```./github-repo-handler.sh <YOUR_ORG/USERNAME> ./<CONFIGURED_JSON_FILE>```
