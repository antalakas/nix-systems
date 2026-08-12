# Sandbox capability request — Tessera dev container

For the owner of the Claude Code sandbox image used on the Tessera repo.

Written 2026-08-09 from inside the container, so the "already present" column
is observed rather than assumed. Everything below is ordered by **value per
unit of risk**; item 1 alone unblocks most of what is currently impossible.

---

## What is already here (please don't re-add)

| | state |
|---|---|
| AWS CLI | **v2.36.8**, present and working |
| AWS credentials | present — `arn:aws:iam::980565428655:user/andreas` — but see §2 |
| kubectl / helm | v1.36.3 / v4.2.3 (no cluster to talk to) |
| node / npm / yarn | present |
| Python | 3.13.14 in a pixi env at `/workspace/.pixi/envs/default` |
| PyPI | reachable (verified: `pip install six` succeeds) |
| GitHub HTTPS + `gh` | working — branches push, PRs open and merge |
| Public S3 (unsigned GET) | working (~1.4 MB/s to us-east-1 — see §4) |
| User | `uid=1000(node)`, **not root**, no sudo |

## What is missing

| | state | blocks |
|---|---|---|
| PostgreSQL server | absent (no binaries, no service) | the entire control plane |
| Docker / dockerd | absent (no binary, no socket) | the documented DB bring-up |
| `pixi` CLI | absent (only the resolved env at `.pixi/envs/default`) | adding conda deps myself |
| Usable AWS permissions | denied by `EnforceMFA` | every cloud phase |

---

## 1. PostgreSQL 16 **with the `vector` extension** — the highest-value ask

**This is the one that matters.** Tessera's control plane is a FastAPI app over
PostgreSQL. Without a database I cannot start the API, so I cannot exercise
*any* dispatch-driven path: queueing work, a node claiming it, lease renewal
and fencing, the drain, or the Ask agent. Those are the core of the product,
and today they are only ever verified by mocks in the test suite — a gap the
project's own notes call out repeatedly ("every bug found by running live").

**It must include the `vector` extension**, not just stock Postgres:
`src/tessera/foundation/db/models.py:31` imports `pgvector.sqlalchemy.Vector`
for the RAG chunk table, and the project's compose file uses
`pgvector/pgvector:pg16` for exactly this reason.

**Preferred form — OS packages in the image, no daemon, no root:**

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      postgresql-16 postgresql-contrib-16 postgresql-16-pgvector \
 && rm -rf /var/lib/apt/lists/*
ENV PATH="/usr/lib/postgresql/16/bin:${PATH}"
```

That is enough. **No running service and no root are required** — with the
binaries on `PATH` I can run an entire cluster in userspace inside the
workspace:

```bash
initdb -D /workspace/.pgdata -U tessera --auth=trust
pg_ctl -D /workspace/.pgdata -o "-p 5433 -k /tmp" -l /tmp/pg.log start
createdb -h localhost -p 5433 -U tessera tessera
```

which matches the app's default
`postgresql+asyncpg://tessera:tessera@localhost:5433/tessera` exactly.

**Alternative if apt packages are awkward:** add `postgresql` and `pgvector` to
the pixi environment (both are on conda-forge), or simply install the `pixi`
CLI so I can add them myself — right now the resolved env exists but the tool
that manages it does not.

**Unblocks:** local plane bring-up · dispatch/claim/lease/fencing end to end ·
the mesh drain watched from the seat · the Ask agent against a real database ·
Phases 3 and 5 of the DRAGEN panel PRD · realistically, most future Tessera
work, since almost every feature touches the plane.

**Risk:** none meaningful. A local database in a container, no ports exposed
outside it, no credentials involved.

---

## 2. An AWS identity that is not MFA-gated

Credentials are already mounted, but they belong to a **personal IAM user**
carrying an `EnforceMFA` policy with an explicit deny. Every call fails the
same way:

```
$ aws s3 ls
AccessDenied … not authorized to perform: s3:ListAllMyBuckets
with an explicit deny in an identity-based policy:
arn:aws:iam::980565428655:policy/EnforceMFA
```

Two separate problems, worth naming separately: an agent cannot satisfy MFA,
and these are the wrong credentials to hand an agent at all — they carry the
owner's whole personal blast radius.

**What I'd ask for instead: a dedicated IAM user (or role) in a separate
account, scoped to this demo.** Pick the tier that matches your risk appetite.

### Tier A — S3 only (no compute; smallest possible grant)

Enough to write and verify the panel output. Does **not** unblock the scale
proof, which needs machines.

```json
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
```

*Note:* reading the 1000 Genomes source data needs **no permission at all** —
those buckets are public and the harness reads them unsigned. The only bucket
that needs a grant is the one I write to.

### Tier B — S3 + tightly scoped EC2 (this is the real unblock)

Phases 1 and 2 measure a single-writer constant and then divide it across W
machines. That needs the ability to launch and terminate instances. Scoped by
region, instance type, and a mandatory tag:

```json
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
```

**Guardrails I'd recommend adding, because IAM cannot express "at most N
instances":**

- an **AWS Budget** on the account with an action that stops instances at a
  ceiling — pick a number; the projected spend is small (see below);
- a low **service quota** on running vCPUs in us-east-1, which *is* a hard cap;
- the `Project=dragen-panel` tag above, so a sweep can find and kill anything
  left behind.

**Expected spend, for calibration.** The minimum credible scale proof is
**~118 GB of reads** — chr21 twice, once at W=1 and once at W=8 — from the
us-east-1 clone bucket, so **transfer is $0**. Cost is a handful of
instance-hours; the sibling atlas PRD budgets `~$30–60` for a much larger run.
The PRD's own rule is to tear the fleet down the same day and record actual
spend against the projection.

### Tier C — you keep the keys

You launch the instances; I get in via **SSM Session Manager** (or an SSH key)
and drive them. No EC2 permissions for me at all. Costs you a few minutes at
the start and end of each run, and is a perfectly reasonable answer if Tier B
is too much.

**Unblocks (B or C):** Phase 1, the single-writer constant · Phase 2,
cross-machine linearity — *the proof the whole PRD exists for* · Phase 4, the
full 4 TB corpus.

---

## 3. Docker-in-Docker — genuinely optional, and I'd deprioritise it

Worth stating plainly: **item 1 removes most of the reason to want this.** The
only thing Docker is used for in daily Tessera work is starting the Postgres
container, and userspace Postgres does that better in a sandbox.

It would still unblock a narrower set of things, if they ever become priorities:

- `kind` clusters, and with them the SDK's **Recipe B** pipeline capability
  (Kubernetes `Job` submission) and **Recipe C** notebook sessions — the
  `demo/mesh/compute/` and `demo/notebooks/` runbooks;
- building and testing node container images locally.

Neither is on the DRAGEN panel's path: that node registers an **in-process**
executor and submits no Jobs. If you add it anyway, rootless Docker or
`podman` would fit the non-root user here better than privileged DinD.

**Verdict: skip unless the Kubernetes recipes come up.**

---

## 4. One networking observation (not a request)

Ranged S3 GETs from this container to us-east-1 run at roughly **1.4 MB/s** —
a 67 MB read takes ~50–70 s. Confirmed by profiling: decompression is 1.6 s/GB
and parsing is negligible, so it is the link, not the code.

This is not a blocker and may be intentional. It is worth knowing because it
means **no throughput number measured in this container is meaningful**, which
is now a written rule in the PRD: local phases publish pass/fail only, and
every performance claim comes from EC2. If raising it is cheap, it would make
local iteration on large-object work noticeably less painful. If not, fine.

---

## Summary

| # | ask | effort | risk | unblocks |
|---|---|---|---|---|
| 1 | **PostgreSQL 16 + pgvector binaries** | one `apt-get` line | none | the local plane, dispatch end to end, Ask, Phases 3 & 5 — and most future work |
| 2 | **Scoped AWS identity** (Tier A / B / C) | one IAM user + policy | tunable | Phases 1, 2, 4 — the cross-machine scale proof |
| 3 | Docker-in-Docker | significant | moderate | k8s recipes only — **skip for now** |
| 4 | S3 throughput | unknown | none | faster iteration; nothing is blocked on it |

**If only one thing happens, make it #1.** It is a single line in the
Dockerfile, needs no daemon and no root, and it converts the plane from
something only mocks have ever exercised into something that can be run.
