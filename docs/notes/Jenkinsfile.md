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

**`pollSCM('H/2 * * * *')`:** Jenkins asks GitHub for new commits about every 2 minutes, because
GitHub can't send webhooks to localhost. `H` spreads the load.
