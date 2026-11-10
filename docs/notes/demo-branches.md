# Branches and demos

| Branch | Based on | What it changes | Expected pipeline result | Demo |
|---|---|---|---|---|
| `main` | n/a | SplitEase v1 + all infrastructure code | CI passes, then **released** (ECR → idle colour → switch) | 1 (v1) |
| `feature/v2` | main | v2: percentage/amount split, version in footer | CI passes (feature branches never deploy). **Merge into `main`** to release it | 1 (v2), 6 |
| `demo/failing-test` | feature/v2 | Rounding "simplification" drops leftover paise | **Unit tests** stage fails (31 tests) | 2 |
| `demo/fake-secret` | feature/v2 | `app/payment_config.py` with a FAKE API key | **Gitleaks** fails (`generic-api-key`) | 3 |
| `demo/vulnerable-image` | feature/v2 | `gunicorn==21.2.0` | **Trivy** fails (CVE-2024-1135, CVE-2024-6827) | 4 |
| `demo/bad-release` | feature/v2 | v2.1: `/health` needs `FX_RATES_URL`, which the deployment doesn't set | CI passes. **Merge into `main`**: deploy to idle → **Health check** fails → no switch | 5 |

## How each demo is run
- **Demos 2–4 (CI gates):** the branches are already on GitHub, and the multibranch job builds each
  one. Open the branch's build to show the red stage. Nothing is pushed to ECR because the release
  stages only run on `main`.
- **Demo 1:** `git switch main && git merge feature/v2 && git push` → the pipeline deploys v2 to
  the idle colour, checks it, and switches. The footer changes to "v2.0.0".
- **Demo 5:** `git merge demo/bad-release && git push` → the health check on the idle colour fails
  ("Target.ResponseCodeMismatch"), the live colour keeps serving, and the idle colour's SSM tag is
  restored. Then `git revert -m 1 HEAD && git push` to put `main` back.
- **Demo 6:** Jenkins → `splitease-rollback` → Build Now.

## Why a fake secret on a branch, not on main
Gitleaks scans the **whole history** of the branch being built. A secret that ever lands on `main`
stays in its history even after you delete the file, and the gate would fail every future build
(that is the point: the secret must be treated as leaked and rotated). The demo secret therefore
lives only on `demo/fake-secret`, and the scan covers only the commits reachable from the branch
being built (`--log-opts=HEAD`).

## About GitHub push protection
The fake key has a made-up prefix (`fk_live_`) that GitHub's push protection does not recognise, so
the push isn't blocked. Gitleaks still flags it with its generic high-entropy API-key rule.
