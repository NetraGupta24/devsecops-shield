# `Jenkinsfile`

**What it does:** The whole CI/CD pipeline, written as code and stored in Git. Jenkins runs it for
every branch.

| # | Stage | Branches | What happens / why |
|---|---|---|---|
| 1 | Checkout | all | Get the commit from GitHub (full history, for Gitleaks) |
| 2 | Unit tests | all | Fresh virtualenv + pytest. Any failure stops the pipeline (demo 2) |
| 3 | Gitleaks | all | Secret scan of **all commits on this branch**; any finding stops it (demo 3). `--redact` hides the secret in the log |
| 4 | Docker build | all | `splitease:build-<N>`, never just `latest`. `--pull` gets the newest patched base image |
| 5 | Trivy | all | Fails on fixable HIGH/CRITICAL (demo 4). See `security/trivy-policy.md` |
| 6 | Push to ECR | **main** | Reached only if 2–5 passed. Only approved images enter the registry |
| 7 | Find idle colour | main | Reads `/splitease/live_color`; idle = the other colour |
| 8 | Deploy to idle colour | main | Writes the new tag to SSM (for future instances), then Ansible updates the running ones |
| 9 | Health check | main | (a) all idle targets healthy in the ALB; (b) `/version` via the **8080 test listener** returns this build |
| 10 | Switch traffic | main | Port 80 → idle colour, 8080 → old colour, SSM `live_color` updated. Then re-checks port 80 |
| 11 | Post | main | Prints the result. On failure **before** the switch: restores the idle colour's SSM tag; production was never touched |

**Credentials:** AWS keys come from Jenkins Credentials (`aws-access-key-id`,
`aws-secret-access-key`, both *Secret text*), and the SSH key from `ec2-ssh-key` (*SSH Username with
private key*). Jenkins masks them in logs, and they never appear in the repository.

**Why only `main` deploys:** feature and demo branches get the full CI checks, but only reviewed code
on `main` is released, which is normal team practice.

**First release only:** the old colour has never run anything (`none`). After the first successful
switch it is given the same release, so it becomes healthy and rollback has a target.

**How builds are triggered (Poll SCM):** GitHub can't send webhooks to `localhost`, so Jenkins
*polls* GitHub instead. In this multibranch setup the polling is the job's **branch indexing**,
which runs every minute (`jenkins/jobs/splitease/config.xml`). It finds new branches and new
commits, and builds whatever changed.

**Lesson learned:** the first version *also* had `triggers { pollSCM('H/2 * * * *') }` in the
Jenkinsfile. Jenkins logs then showed two builds for one commit, 17 s apart: one "Started by an SCM
change" (pollSCM) and one from "Branch indexing". For CI that only wastes time, but for a release
the second run would deploy again and **flip traffic to the other colour**. Keeping one polling
mechanism fixed it.

**Lesson learned: "Load key: error in libcrypto".** In the first real release, Ansible got
`Permission denied (publickey)` even though the same key worked from the laptop. The log showed
`Load key "****": error in libcrypto`: SSH couldn't even read the key Jenkins handed it. A test on a
throwaway key reproduced the error for both causes: a **missing final newline** and **Windows (CRLF)
line endings**. Browsers can submit text-box contents with CRLF, so a perfectly pasted key can still
break. The deploy stage now writes a cleaned copy (`tr -d '\r'`, plus a final newline) into a
private `mktemp -d` folder (mode 700) and deletes it with `trap ... EXIT`. The key is never printed.
(That release still succeeded, because the ASG replaced the instance and user data booted the new
version from SSM, which is the designed fallback.)

**Second lesson: protect the pipeline from a broken credential.** Cleaning line endings wasn't
enough (build #9 still got `error in libcrypto`), so the stored key had another defect from the
copy-paste. Two changes:
1. **Pre-flight key check:** before Ansible runs, `ssh-keygen -y` tests the key. If it fails, the
   stage stops immediately with yes/no facts (BEGIN/END lines present? public key pasted by
   mistake? how many lines, any spaces?) and **never prints key material**. Without this, a broken
   key looked like "host unreachable", which the stage deliberately tolerates (for ASG
   replacements), and the failure only surfaced minutes later at the version check.
2. **Safe way to copy the key into Jenkins:** `clip.exe < ~/.ssh/splitease-deploy` copies the file's
   exact bytes to the Windows clipboard, avoiding terminal-copy damage (wrapped lines, padding
   spaces). Afterwards, clear the clipboard with `printf '' | clip.exe`.

**What build #9 proved:** green was healthy but still running the *old* build. The health gate alone
would have passed, but the **version check on the test listener (8080) refused to switch**, the
idle colour's SSM tag was restored, and v1 kept serving users. That is exactly why the pipeline
checks *both* health and version.
