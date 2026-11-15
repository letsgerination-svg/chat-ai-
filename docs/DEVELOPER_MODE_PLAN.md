# Developer Mode and Cloud Integrations

## Product direction

The iOS app is being extended from a chat client into a mobile development assistant. The assistant should inspect a project, propose a patch, explain changes, and request explicit approval before applying changes or deploying resources.

## Planned capabilities

1. Project workspace with a local file tree, syntax-aware editor, diff preview, and project context.
2. A constrained command runner for build, test, lint, and diagnostic commands. Commands run in an isolated workspace; destructive or networked commands require approval.
3. GitHub integration: authenticate, browse repositories and branches, read files, create/update files, create branches, commit changes, open pull requests, and inspect Actions results.
4. Cloudflare integration: verify credentials, list accounts and Workers, inspect deployments and logs, and later deploy or update Workers and Pages after confirmation.
5. Agent workflow: inspect -> plan -> propose diff -> user approval -> apply -> run checks -> report exact results.

## Credential model

- GitHub fine-grained personal access token is the initial connection method. Store it in iOS Keychain under account github-access-token.
- Suggested initial GitHub permissions: Metadata (read), Contents (read/write), and Pull requests (read/write), scoped only to selected repositories. Add Actions read only when workflow inspection is enabled.
- Cloudflare API token is the initial connection method. Store it in iOS Keychain under account cloudflare-api-token.
- Cloudflare token should be scoped to the intended account and only the required Workers Scripts and account read permissions. Do not use the Global API Key.
- Never embed credentials in the IPA, source files, logs, prompts, analytics, or project exports.
- Tokens are sent only to their respective official APIs over HTTPS. A disconnect action deletes the local Keychain item.

## Implementation status

- DeveloperIntegrations.swift contains first-pass native GitHub and Cloudflare REST clients.
- GitHub client supports token validation, repository listing, text-file reads/writes, and pull-request creation.
- Cloudflare client supports token validation, account listing, and Workers script listing.
- UI for connecting/disconnecting accounts and selecting a repository/account is still to be wired into Settings.
- The local project workspace, command runner, diff approval flow, deployments, and Actions UI remain future implementation stages.
- The GitHub/Cloudflare clients must pass CI and be exercised against real user-authorized test accounts before being called complete.

## Safety boundaries

- Read-only operations may run after connection.
- File writes, branch/commit creation, pull requests, and Cloudflare deployments require a clear review/approval step.
- Deletion, production changes, and secret modifications require a second explicit confirmation.
- The assistant must show the exact repository/account, file path, diff, and target environment before applying a change.