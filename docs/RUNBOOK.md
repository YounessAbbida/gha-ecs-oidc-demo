# Runbook

Exact order to bring the demo up, record the proof, and tear it down.
Commands run from the repository root unless a step says otherwise.

## 0. Prerequisites

- Terraform >= 1.10 (CI uses 1.16.5), AWS CLI v2, GitHub CLI (`gh`), `jq`.
- An AWS CLI profile for the target account with admin rights, used only on
  your machine for the two `terraform apply` runs (for example IAM Identity
  Center: `aws sso login --profile demo`). GitHub never receives these
  credentials.
- The repository `YounessAbbida/gha-ecs-oidc-demo` exists on GitHub and this
  code is on `main`. Until step 3 sets the repository variables, the deploy
  job is skipped (not failed).

```bash
export AWS_PROFILE=demo
export AWS_REGION=eu-west-3
export REPO=YounessAbbida/gha-ecs-oidc-demo
aws sts get-caller-identity   # confirm the account before creating anything
```

## 1. Bootstrap (once per account)

Creates the state bucket, the GitHub OIDC provider and the budget. The state
is local (`terraform/bootstrap/terraform.tfstate`, gitignored); keep it until
the final teardown.

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set budget_email.
# If the account already has a GitHub OIDC provider: create_oidc_provider = false
terraform init
terraform apply
terraform output
cd ../..
```

AWS Budgets sends the alerts to `budget_email`; no confirmation is needed.

## 2. Infra with `desired_count = 0`

The service starts with zero tasks: the first task definition points at a
`:bootstrap` tag that does not exist yet.

```bash
cd terraform/infra

# Backend config (gitignored).
printf 'bucket = "%s"\nkey    = "infra/terraform.tfstate"\nregion = "%s"\n' \
  "$(terraform -chdir=../bootstrap output -raw state_bucket_name)" "$AWS_REGION" > backend.hcl

# Variables (gitignored). The numeric IDs go into the OIDC subject: GitHub
# repositories created after 2026-07-15 use the immutable owner@id/repo@id format.
printf 'desired_count   = 0\ngithub_owner_id = "%s"\ngithub_repo_id  = "%s"\n' \
  "$(gh api "repos/${REPO}" --jq .owner.id)" "$(gh api "repos/${REPO}" --jq .id)" > terraform.tfvars

terraform init -backend-config=backend.hcl
terraform apply
terraform output
cd ../..
```

`deploy_role_oidc_subject` is the only `sub` claim the role accepts. If the
repository uses the legacy `owner/name` subject format instead (created before
2026-07-15 and not opted in), set both IDs to `""` and apply again. Step 4
shows which format GitHub actually sends.

## 3. GitHub setup

### 3a. `production` environment, deployable from `main` only

```bash
gh api -X PUT "repos/${REPO}/environments/production" \
  -F "deployment_branch_policy[protected_branches]=false" \
  -F "deployment_branch_policy[custom_branch_policies]=true"

gh api -X POST "repos/${REPO}/environments/production/deployment-branch-policies" \
  -f name=main -f type=branch
```

This is what makes the `sub` condition meaningful: only a job on `main` can
run in `production`, so only it receives
`repo:...:environment:production`.

Optional for a client setup: add required reviewers to the environment
(Settings, Environments, production) so each deploy waits for approval.

### 3b. Repository variables

Variables, not secrets: none of these values is sensitive, and there is no AWS
key to store.

```bash
gh variable set AWS_REGION          --repo "$REPO" --body "$AWS_REGION"
gh variable set AWS_DEPLOY_ROLE_ARN --repo "$REPO" --body "$(terraform -chdir=terraform/infra output -raw deploy_role_arn)"
gh variable set ALB_URL             --repo "$REPO" --body "$(terraform -chdir=terraform/infra output -raw alb_url)"
```

### 3c. Branch protection on `main`

Pull request required, the four CI jobs must pass, no force pushes. Status
check names only exist after `ci.yml` has run once, so open a first PR (any
small change) before this call if GitHub rejects the contexts.

```bash
gh api -X PUT "repos/${REPO}/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["app", "terraform", "checkov", "actionlint"] },
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

`required_approving_review_count` is 0 because this is a one-person repository;
for a client it should be at least 1.

## 4. First deploy

```bash
gh workflow run deploy.yml --repo "$REPO" --ref main
sleep 5
gh run watch --repo "$REPO" "$(gh run list --repo "$REPO" --workflow deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

The job assumes the deploy role through OIDC, pushes
`<account>.dkr.ecr.<region>.amazonaws.com/gha-ecs-oidc-demo:<commit-sha>`,
registers a new task definition revision with that image and points the
service at it. With `desired_count = 0` the rollout finishes at once, with no
task running.

If the "Configure AWS credentials" step fails with `Not authorized to perform
sts:AssumeRoleWithWebIdentity`, the subject format does not match (see step 2).

## 5. Scale to `desired_count = 1`

```bash
cd terraform/infra
sed -i.bak 's/^desired_count *= *0/desired_count   = 1/' terraform.tfvars && rm terraform.tfvars.bak
terraform apply   # the plan must show only desired_count: 0 -> 1
cd ../..

aws ecs wait services-stable --cluster gha-ecs-oidc-demo --services gha-ecs-oidc-demo
curl -s "$(terraform -chdir=terraform/infra output -raw alb_url)/"
# {"service":"gha-ecs-oidc-demo","version":"<commit-sha>"}
```

The service ignores `task_definition` changes in Terraform, so this apply
keeps the revision deployed by the workflow; it only changes the task count.

Then merge a visible change to `app/main.py` through a PR to show a second,
fully automatic deploy (new SHA in the response).

## 6. Negative test

```bash
gh workflow run oidc-negative-test.yml --repo "$REPO" --ref main
```

Expected: the run is green, the log prints the token's
`sub = repo:...:ref:refs/heads/main`, and the summary shows the
`AccessDenied` error returned by STS.

## 7. Record proof

Save into `docs/proof/` (redact the account ID if you prefer):

| File | Shows |
|---|---|
| `01-deploy-run.png` | Green `deploy` run and its job summary (image tag, ALB URL). |
| `02-app-response.png` | The ALB URL returning the commit SHA as `version`. |
| `03-negative-test.png` | Green `oidc-negative-test` run with the `AccessDenied` message. |
| `04-trust-policy.png` | IAM console, deploy role, Trust relationships. |
| `05-cloudtrail.png` | `AssumeRoleWithWebIdentity` events: one success, one `AccessDenied`. |
| `06-no-secrets.png` | Settings, Secrets and variables: no AWS secrets, only the variables. |

CloudTrail query for the last item:

```bash
aws cloudtrail lookup-events --region "$AWS_REGION" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 10 --output json \
| jq -r '.Events[] | .EventTime + "  " + (.CloudTrailEvent | fromjson | (.errorCode // "OK") + "  " + (.requestParameters.roleSessionName // "-"))'
```

Commit the screenshots through a PR and link them in the README proof section.

## 8. Destroy

```bash
# Workload first. ECR force_delete removes the pushed images with the repository.
cd terraform/infra
terraform destroy
cd ../..

# Task definition revisions registered by the workflow are not in Terraform
# state. They cost nothing; deregister them for a clean account.
for arn in $(aws ecs list-task-definitions --family-prefix gha-ecs-oidc-demo --query 'taskDefinitionArns[]' --output text); do
  aws ecs deregister-task-definition --task-definition "$arn" > /dev/null
done

# Remove the variables so the deploy job is skipped again.
for v in AWS_DEPLOY_ROLE_ARN AWS_REGION ALB_URL; do gh variable delete "$v" --repo "$REPO"; done
```

The bootstrap stack can stay (empty bucket, OIDC provider and budget cost
nothing). To remove it as well:

```bash
cd terraform/bootstrap
echo 'state_bucket_force_destroy = true' >> terraform.tfvars
terraform apply     # stores force_destroy in state first
terraform destroy
cd ../..
```

Final check the next day: Billing, Cost Explorer shows no NAT gateway, load
balancer or Fargate usage.
