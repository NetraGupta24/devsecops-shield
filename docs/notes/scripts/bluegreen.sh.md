# `scripts/bluegreen.sh`

**What it does:** Small Blue-Green helper commands (AWS CLI + jq), used by **both** `Jenkinsfile`
and `Jenkinsfile.rollback`, so the switching logic exists in exactly one place.

| Command | What it does |
|---|---|
| `live-color` | Reads `/splitease/live_color` from SSM (must be blue/green) |
| `other-color X` | blue ↔ green |
| `get-tag X` / `set-tag X TAG` | Read or write `/splitease/X/image_tag` |
| `wait-healthy X [secs]` | Polls the target group until **every** non-draining target is `healthy` (fails after the timeout) |
| `check-version PORT BUILD` | Calls `http://<alb>:PORT/version` until it returns BUILD **5 times in a row** (so *all* instances behind that listener run the new build) |
| `switch X` | Port 80 → X, port 8080 → the other colour, `/splitease/live_color = X` |
| `status` | Prints what runs where, plus the live URL and version |

`set -euo pipefail` makes the script stop at the first error, and Jenkins then marks the stage
failed.
