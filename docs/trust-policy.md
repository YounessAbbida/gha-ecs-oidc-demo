# Deploy role trust policy

The trust policy Terraform renders for the deploy role
(`terraform/infra/iam_deploy.tf`). The account ID and the GitHub numeric IDs
are placeholders.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GitHubActionsOidc",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:YounessAbbida@11111111/gha-ecs-oidc-demo@222222222:environment:production"
        }
      }
    }
  ]
}
```

On the role itself: `max_session_duration = 3600`.

## Each element

| Element | Value | Why |
|---|---|---|
| `Principal.Federated` | the account's GitHub OIDC provider | Only tokens issued by GitHub Actions (`token.actions.githubusercontent.com`) are considered. IAM checks the signature and issuer before any condition. |
| `Action` | `sts:AssumeRoleWithWebIdentity` | The only way in is a GitHub OIDC token. There is no `sts:AssumeRole`, so no IAM user or other role can assume it. |
| `aud` | `sts.amazonaws.com` | The token was requested for AWS STS. A GitHub token minted for another relying party (another cloud, Vault, ...) is rejected. |
| `sub` | `repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:production` | GitHub puts this exact value in the token only for a job of this repository that declares `environment: production`. Pull requests, other branches without the environment, forks and other repositories get a different `sub`. |
| `StringEquals`, not `StringLike` | exact match | No `*` anywhere. `repo:YounessAbbida/*` would let every repository of the owner deploy. |
| `max_session_duration` | 3600 s | Credentials expire after one hour at most; a deploy takes a few minutes. |

## Subject format

GitHub has two `sub` formats for the repository part:

| Format | Example | Used by |
|---|---|---|
| Immutable (IDs) | `repo:YounessAbbida@11111111/gha-ecs-oidc-demo@222222222:environment:production` | Repositories created or renamed after 2026-07-15, or opted in |
| Legacy (names) | `repo:YounessAbbida/gha-ecs-oidc-demo:environment:production` | Older repositories that did not opt in |

Terraform builds the immutable form when `github_owner_id` and
`github_repo_id` are set, and the legacy form when both are empty. The
immutable form is stronger: if the repository were deleted and someone
re-created one with the same name, its IDs would differ and the trust would not
match. The `deploy_role_oidc_subject` output shows the exact value in use.

## What other jobs receive

| Where the job runs | `sub` in its token | Result |
|---|---|---|
| `deploy.yml` on `main`, `environment: production` | `repo:<repo>:environment:production` | allowed |
| A job on `main` without an environment (`oidc-negative-test.yml`) | `repo:<repo>:ref:refs/heads/main` | denied |
| A pull request | `repo:<repo>:pull_request` | denied |
| Another repository or a fork | `repo:<other-repo>:...` | denied |

`oidc-negative-test.yml` runs the second case on demand and fails unless STS
answers `AccessDenied`.

## Settings outside the policy that it relies on

1. **Environment branch rule.** The `production` environment accepts
   deployments from `main` only. Without it, any branch could declare
   `environment: production` and receive the allowed `sub`.
2. **Branch protection on `main`.** Changes reach `main`, and therefore
   production, only through a pull request with passing checks.
3. **Default subject template.** The policy assumes GitHub's default claim
   layout. If the OIDC subject template is customized for the repository or
   organization, the `sub` value has to be updated to match.

## Permissions of the role

| Statement | Actions | Resource |
|---|---|---|
| `EcrLogin` | `ecr:GetAuthorizationToken` | `*` (no resource-level support) |
| `EcrPushPullThisRepo` | layer upload actions, `PutImage`, `BatchGetImage`, `BatchCheckLayerAvailability`, `GetDownloadUrlForLayer` | this ECR repository |
| `EcsTaskDefinitions` | `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition` | `*` (describe has no resource-level support; a new revision has no ARN before it is registered) |
| `EcsDeployThisService` | `ecs:UpdateService`, `ecs:DescribeServices` | this ECS service |
| `PassOnlyTaskRolesToEcsTasks` | `iam:PassRole` | the execution and task roles, only with `iam:PassedToService = ecs-tasks.amazonaws.com` |

Everything else is implicitly denied: no other `iam:` action, no other
repository, cluster or service, no access to the Terraform state bucket.

What `RegisterTaskDefinition` on `*` still allows: registering a task
definition in any family. It cannot run it (no `ecs:RunTask`, and
`UpdateService` is limited to this service), and the only roles it can attach
are the two above, because of the `PassRole` statement.
