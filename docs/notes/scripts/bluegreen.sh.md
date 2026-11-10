# `scripts/bluegreen.sh`

**What it does:** Small Blue-Green helper commands (AWS CLI + jq), used by **both** `Jenkinsfile`
and `Jenkinsfile.rollback`, so the switching logic exists in exactly one place.

| Command | What it does |
|---|---|
| `live-color` | Reads `/splitease/live_color` from SSM (must be blue/green) |
| `other-color X` | blue ↔ green |
| `get-tag X` / `set-tag X TAG` | Read or write `/splitease/X/image_tag` |
| `wait-healthy X [secs] [n]` | Polls the target group until **every** non-draining target has been `healthy` for **n checks in a row** (default 5 × 15 s). Fails fast if the app answers `/health` with an error code (`Target.ResponseCodeMismatch`) for ~1 min |
| `check-version PORT BUILD` | Calls `http://<alb>:PORT/version` until it returns BUILD **5 times in a row** (so *all* instances behind that listener run the new build) |
| `switch X` | Port 80 → X, port 8080 → the other colour, `/splitease/live_color = X` |
| `status` | Prints what runs where, plus the live URL and version |

`set -euo pipefail` makes the script stop at the first error, and Jenkins then marks the stage
failed.

## A bug found while testing (good viva story)
The first version returned as soon as the targets showed `healthy`. A mocked test of a *bad release*
showed the flaw. Right after Ansible replaces a container, the ALB still shows the **old** container's
`healthy` status, because it needs `unhealthy_threshold × interval = 3 × 15 s = 45 s` to notice the
new container failing. The pipeline would have switched users onto a broken release. The fix is to
require **5 healthy checks in a row (60 s)**, which is longer than the ALB's detection time. The
rollback job only needs 2, because nothing was just deployed to the colour it switches to.
