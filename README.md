<div align="center">

# 🏗️ Terraform / Terragrunt Infra Template

**Multi-environment AWS infrastructure, wired up for plan-on-PR and apply-on-merge.**

[![Terraform](https://img.shields.io/badge/Terraform-1.10.0-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Terragrunt](https://img.shields.io/badge/Terragrunt-0.67.0-2E7EED?logo=terraform&logoColor=white)](https://terragrunt.gruntwork.io/)
[![AWS](https://img.shields.io/badge/AWS-OIDC-FF9900?logo=amazonaws&logoColor=white)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html)
[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-CI%2FCD-2088FF?logo=githubactions&logoColor=white)](.github/workflows)
[![Trivy](https://img.shields.io/badge/Trivy-IaC%20Scan-1904DA?logo=aquasec&logoColor=white)](.github/workflows/trivy.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## ✨ What you get

- 🌐 **Multi-account, multi-env** — `dev` / `qa` / `prod` isolated by folder and IAM role.
- 🔁 **DRY config** via a single root `terragrunt.hcl` — backend, provider, and tags in one place.
- 🤖 **Plan on PR, apply on merge** — sticky comments with the full plan, per-env concurrency.
- 🔐 **OIDC-only** to AWS — no long-lived access keys anywhere.
- 🛡️ **IaC scanning** on every PR via Trivy (HIGH/CRITICAL gate).
- 🎯 **Smart change detection** — only affected environments plan/apply; module changes fan out to all.

---

## 📁 Repository layout

```text
terraform/
├── terragrunt.hcl                # 🔧 Shared root config (backend, provider, tags)
├── environments/
│   ├── dev/
│   │   ├── env.hcl               # Per-env locals (name, later: account id, etc.)
│   │   └── terragrunt.hcl        # Includes the root config
│   ├── qa/
│   │   ├── env.hcl
│   │   └── terragrunt.hcl
│   └── prod/
│       ├── env.hcl
│       └── terragrunt.hcl
└── modules/
    └── sample-module/            # Reusable module used by every environment

.github/workflows/
├── terraform-plan.yml            # ▶️  `terragrunt plan` on PRs, comments result
├── terraform-apply.yml           # 🚀 `terragrunt apply` on merge to main
└── trivy.yml                     # 🛡️  IaC scan on PRs, comments findings
```

---

## 📚 Table of contents

1. [Things you MUST change](#1-️-things-you-must-change-before-this-template-works)
2. [AWS setup — OIDC & IAM](#2-️-aws-setup--letting-github-actions-assume-the-roles)
3. [GitHub setup](#3--github-setup)
4. [Local usage](#4--local-usage)
5. [How CI decides what to deploy](#5--how-the-ci-decides-what-to-deploy)
6. [Onboarding checklist](#6--onboarding-checklist)

---

## 1. ⚠️ Things you MUST change before this template works

> 🔍 **Rule of thumb:** search the repo for `REPLACE_ME_` — every match is a placeholder you need to fill in.

### 1a. 📝 [`terraform/terragrunt.hcl`](terraform/terragrunt.hcl)

| Local | Current value | What to set it to |
|---|---|---|
| `project` | `REPLACE_ME_PROJECT_NAME` | Short project slug (e.g. `billing-api`). Used in the state-file key and tags. |
| `team` | `REPLACE_ME_TEAM_NAME` | Owning team name. Applied as a default tag. |
| `region` | `us-east-1` | Change if you deploy to a different AWS region. |

Also confirm the state bucket name pattern is what you want:

```hcl
bucket = "thryv-${local.environment}-infra-tf-state"
```

> 🪣 **The bucket must already exist** in each account before the first `terragrunt init` — Terragrunt won't create it for you with this config.

### 1b. 🔑 Workflow role map — [`terraform-plan.yml`](.github/workflows/terraform-plan.yml) & [`terraform-apply.yml`](.github/workflows/terraform-apply.yml)

Both files define an `AWS_ROLE_ARNS` map keyed by environment folder name:

```yaml
AWS_ROLE_ARNS: |
  {
    "dev":  "arn:aws:iam::REPLACE_ME_DEV_ACCOUNT_ID:role/REPLACE_ME_GHA_ROLE",
    "qa":   "arn:aws:iam::REPLACE_ME_QA_ACCOUNT_ID:role/REPLACE_ME_GHA_ROLE",
    "prod": "arn:aws:iam::REPLACE_ME_PROD_ACCOUNT_ID:role/REPLACE_ME_GHA_ROLE"
  }
```

Replace each `REPLACE_ME_*` with the real AWS account ID and IAM role name for that environment.

> ➕ **Adding a new environment** = create `terraform/environments/<name>/` **and** add a matching entry here. Missing map entries fail fast by design.

---

## 2. ☁️ AWS setup — letting GitHub Actions assume the roles

The workflows use **OIDC** (no long-lived AWS keys). For each AWS account (`dev`, `qa`, `prod`) do this once.

### 2a. 🪪 Create the GitHub OIDC provider in the account

If not already present:

- **Provider URL:** `https://token.actions.githubusercontent.com`
- **Audience:** `sts.amazonaws.com`

Terraform:

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"] # any value; AWS ignores it since 2023
}
```

### 2b. 👤 Create the IAM role that GitHub will assume

The role's **trust policy** must restrict which repo/branch/PR can assume it. Replace `<ORG>/<REPO>` with your repo (e.g. `my-org/template-infra-project-repository`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:<ORG>/<REPO>:pull_request",
            "repo:<ORG>/<REPO>:ref:refs/heads/main",
            "repo:<ORG>/<REPO>:environment:<ENV>"
          ]
        }
      }
    }
  ]
}
```

**Recommended split:**

| Role type | Trust subs | Permissions |
|---|---|---|
| 🔎 **Plan role** (PR runs) | `pull_request` | Read-only (e.g. `ReadOnlyAccess`) + state bucket R/W |
| 🚀 **Apply role** (merge to main) | `ref:refs/heads/main` and/or `environment:<env>` | Only the write actions your modules actually use |

> ℹ️ You can either create separate `..._plan` / `..._apply` roles per env or one role per env used by both flows. The workflow map only tracks one ARN per env — if you split them, split the workflow env maps too.

### 2c. 🗄️ Attach the state-backend permissions

Every role needs read/write on the S3 state bucket. With `use_lockfile = true` in the root `terragrunt.hcl`, the lock is a `.tflock` object in the same bucket — **no DynamoDB required**.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::thryv-<ENV>-infra-tf-state",
        "arn:aws:s3:::thryv-<ENV>-infra-tf-state/*"
      ]
    }
  ]
}
```

### 2d. 📥 Paste the role ARNs into the workflows

Put each account's role ARN into `AWS_ROLE_ARNS` in both [`terraform-plan.yml`](.github/workflows/terraform-plan.yml) and [`terraform-apply.yml`](.github/workflows/terraform-apply.yml).

---

## 3. 🐙 GitHub setup

> 🛡️ **Branch protection on `main`** — require these checks before merge:
> - `Format check`
> - `Plan <env>` (per affected environment)
> - `Trivy IaC scan`
>
> The merge itself is the approval gate — apply runs automatically for every affected env after merge.

---

## 4. 💻 Local usage

Once the placeholders are replaced:

```bash
aws sso login --profile <your-profile>
export AWS_PROFILE=<your-profile>

cd terraform/environments/dev
terragrunt init
terragrunt plan
terragrunt apply
```

Run across every env under a folder with `terragrunt run-all plan` / `run-all apply`.

---

## 5. 🧭 How the CI decides what to deploy

Both plan and apply workflows share the same detection logic:

| Files changed | Result |
|---|---|
| `terraform/environments/<env>/**` | 🎯 Plan/apply that env only |
| `terraform/modules/**` | 📦 Plan/apply **every** env (modules are shared) |
| `terraform/terragrunt.hcl` | 🌍 Plan/apply **every** env (root config affects all) |

> 🎛️ The apply workflow additionally accepts a `workflow_dispatch` input to force-apply a comma-separated list of environments.

The Trivy scan runs on every PR that touches `terraform/**`, independent of the matrix — one scan covers all modules and envs.

---

## 6. ✅ Onboarding checklist

- [ ] Replace `project` and `team` in [`terraform/terragrunt.hcl`](terraform/terragrunt.hcl)
- [ ] Confirm/change `region` and the state bucket name pattern
- [ ] Create the S3 state bucket in each AWS account
- [ ] Create the GitHub OIDC provider + per-env IAM role in each account
- [ ] Put role ARNs into `AWS_ROLE_ARNS` in both workflow files
- [ ] Replace the empty `modules/sample-module/*.tf` files with real module code (or delete the module folder if you don't use modules yet)
- [ ] Turn on branch protection for `main` with the required checks listed above

---

<div align="center">

Made with 🧱 Terraform · 🧬 Terragrunt · ☁️ AWS · 🐙 GitHub Actions

</div>
