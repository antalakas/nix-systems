# Giving a sandbox profile its own AWS identity

A walkthrough for when you have time to cut the scoped IAM user. Background and
the reasoning for each tier is in [sandbox-capability-request.md](sandbox-capability-request.md) §2;
this is the operational half — what to actually run, in order.

The sandbox side is already done. `claude-sandbox` prefers
`~/.claude-profiles/<profile>/.aws` over the host's `~/.aws` and prints which
one it picked at startup, so the only thing standing between here and a working
scoped identity is the IAM work below.

## Why not just keep mounting `~/.aws`

Two independent reasons, worth keeping separate because they have different
fixes:

- **The personal user is MFA-gated.** Its `EnforceMFA` policy carries an
  explicit deny that no agent can clear — an agent cannot produce a second
  factor. Every call fails identically regardless of what else you grant.
- **It is the wrong blast radius.** Even if MFA were not in the way, that
  identity can reach everything you can reach. A sandbox should hold the
  smallest credential that does the job.

Only the second is fixed by scoping. The first is fixed by the new user simply
not having that policy attached.

## Before you start

- Decide **which account**. A separate account under the same org is the clean
  answer: a blast radius that stops at the account boundary, one place to look
  for spend, and teardown is deleting an account rather than auditing a policy.
  Same-account is acceptable if the policies below are the only thing the user
  has — but you lose the hard boundary.
- Decide **which tier** (see below). You can start at A and add B later; the
  user and its access key do not change, only the attached policy.
- Have an **admin session with MFA satisfied** on the host — you are creating
  IAM resources, which your personal identity *can* do once MFA is live.
- **If you want Tier B, check the vCPU quota now, not on the run day.** New
  accounts default to a low running-on-demand-vCPU limit, often far below the
  64 vCPUs that eight `c6i.2xlarge` need. Increases are a request that can take
  hours to days, and Service Quotas cannot lower a limit below the default, so
  the default is your friend — raise it once, to exactly what W=8 needs, and no
  further.

  ```bash
  aws service-quotas get-service-quota \
      --service-code ec2 --quota-code L-1216C47A --region us-east-1
  ```

## 1. Create the user

```bash
USER_NAME=tessera-sandbox
aws iam create-user --user-name "$USER_NAME"
```

No console password, no MFA, no groups. It exists only to hold an access key.

## 2. Attach the policy for your tier

### Tier A — S3 only

Enough to write and verify panel output; does **not** unblock the scale proof.
Reading the 1000 Genomes source data needs no grant at all — those buckets are
public and read unsigned.

```bash
cat > /tmp/tier-a.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::tessera-panel-demo",
      "arn:aws:s3:::tessera-panel-demo/*"
    ]
  }]
}
JSON
aws iam put-user-policy --user-name "$USER_NAME" \
    --policy-name tessera-panel-s3 --policy-document file:///tmp/tier-a.json
```

Create the bucket if it does not exist. `us-east-1` is the one region that
takes no `LocationConstraint` — passing one there is an error:

```bash
aws s3api create-bucket --bucket tessera-panel-demo --region us-east-1
aws s3api put-public-access-block --bucket tessera-panel-demo \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### Tier B — S3 + scoped EC2

The real unblock: Phases 1 and 2 measure a single-writer constant and divide it
across W machines, which needs machines. Added alongside the Tier A policy, not
instead of it — fill in `<ACCOUNT>` first:

```bash
cat > /tmp/tier-b.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LaunchTaggedOnly",
      "Effect": "Allow",
      "Action": "ec2:RunInstances",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1",
          "aws:RequestTag/Project": "dragen-panel"
        },
        "StringLike": { "ec2:InstanceType": ["c6i.*", "m6i.*"] }
      }
    },
    {
      "Sid": "ManageOnlyWhatILaunched",
      "Effect": "Allow",
      "Action": ["ec2:TerminateInstances", "ec2:StopInstances", "ec2:CreateTags"],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "ec2:ResourceTag/Project": "dragen-panel" }
      }
    },
    {
      "Sid": "ReadOnlyDiscovery",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances", "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceTypes", "ec2:DescribeImages",
        "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassOnlyTheNodeRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::<ACCOUNT>:role/dragen-panel-node"
    }
  ]
}
JSON
aws iam put-user-policy --user-name "$USER_NAME" \
    --policy-name tessera-panel-ec2 --policy-document file:///tmp/tier-b.json
```

It is scoped three ways at once — region, instance family, and a mandatory
`Project=dragen-panel` tag on launch — and the management statement only
touches resources already carrying that tag. The `iam:PassRole` statement names
exactly one role, which is what stops an instance from being launched with a
more privileged profile than intended.

**IAM cannot express "at most N instances."** Nothing in that policy prevents a
loop from launching a hundred of them. Add the guardrails in step 3.

### Tier C — you keep the keys

Skip the EC2 policy entirely, keep Tier A, and launch instances yourself; the
sandbox gets in via SSM Session Manager or an SSH key. Costs you a few minutes
at each end of a run and gives up nothing else. A perfectly reasonable answer
if B feels like too much.

## 3. Guardrails (Tier B only)

Do all three. They fail in different directions, which is the point.

- **A budget with a stop action.** This is the only one that reacts to spend
  rather than to shape. It needs a budgets-action IAM role that can stop EC2
  instances — create that role first, then the budget with an
  `--action-threshold` wired to it. Pick a ceiling well above the projection
  and well below anything that would hurt.
- **The vCPU quota**, from the pre-flight above. Unlike the budget, this is a
  hard cap enforced at launch, not an after-the-fact reaction.
- **The `Project=dragen-panel` tag**, already mandatory in the policy. This is
  what makes the teardown sweep in the last section possible.

Expected spend for calibration: ~118 GB of reads (chr21 twice, W=1 then W=8)
from the us-east-1 clone bucket, so transfer is $0 and cost is a handful of
instance-hours. The sibling atlas PRD budgets $30–60 for a substantially larger
run.

## 4. Mint the access key and wire it into the profile

```bash
aws iam create-access-key --user-name "$USER_NAME"
```

That prints the secret **once**. Write it straight into the profile — pick the
profile you actually open Tessera with:

```bash
PROFILE=work
mkdir -p ~/.claude-profiles/$PROFILE/.aws
chmod 700 ~/.claude-profiles/$PROFILE/.aws

cat > ~/.claude-profiles/$PROFILE/.aws/credentials <<'INI'
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
INI
chmod 600 ~/.claude-profiles/$PROFILE/.aws/credentials

cat > ~/.claude-profiles/$PROFILE/.aws/config <<'INI'
[default]
region = us-east-1
output = json
INI
```

Set the region here rather than relying on `AWS_REGION` in the container — the
policy's `aws:RequestedRegion` condition means a call that defaults to the
wrong region fails with an access denial rather than an obvious error.

The mount is **read-only**, so `aws configure` inside the container cannot work
and neither can `aws sso login`. Static keys for a scoped user are the intended
shape here; write any change on the host.

## 5. Verify

The startup banner tells you which credentials were selected before anything
runs — look for `(profile)`:

```
   AWS:     /home/andreas/.claude-profiles/work/.aws (profile)
```

If it says `(host fallback — your personal identity)`, the directory is missing
or misnamed and you are back on the MFA-gated user. Inside the sandbox:

```bash
aws sts get-caller-identity          # should be tessera-sandbox, not user/andreas
aws s3 ls s3://tessera-panel-demo    # should succeed, and be the only bucket you can list
aws s3 ls                            # should still fail — ListAllMyBuckets is not granted
```

That last one failing is the check working, not a problem. Tier B adds:

```bash
aws ec2 describe-instances --region us-east-1 --max-items 1
aws ec2 describe-instances --region eu-west-1 --max-items 1   # discovery is unscoped by region
```

## Teardown

After the run — the PRD's own rule is same-day teardown with actual spend
recorded against the projection:

```bash
aws ec2 describe-instances --region us-east-1 \
    --filters "Name=tag:Project,Values=dragen-panel" \
              "Name=instance-state-name,Values=running,pending,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text
# then terminate whatever that lists
```

When the project is finished, delete the access key — that alone neutralises
the credential wherever a copy of it ended up:

```bash
aws iam list-access-keys --user-name "$USER_NAME"
aws iam delete-access-key --user-name "$USER_NAME" --access-key-id AKIA...
rm -rf ~/.claude-profiles/$PROFILE/.aws
```

With the directory gone the sandbox silently falls back to `~/.aws` again. If
you would rather it mount nothing at all, run with
`CLAUDE_SANDBOX_AWS_DIR=none`.

## Rotating or reusing this for another project

Nothing above is Tessera-specific except the bucket name, the tag value, and
the policy names. For a second project, prefer a second IAM user over widening
this one — the whole value of the arrangement is that a leaked key reaches
exactly one project's resources.
