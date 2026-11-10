# Trivy vulnerability policy (Security Gate 2)

## Rule

```
trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 splitease:build-<N>
```

| Finding | Pipeline result |
|---|---|
| CRITICAL or HIGH **with a fixed version available** | **Build fails.** The image never reaches ECR |
| CRITICAL or HIGH with **no fix yet** (`--ignore-unfixed`) | Not blocking (nothing we can upgrade to yet) |
| MEDIUM / LOW | Not blocking |

## What is scanned
- **OS packages** of the image (Debian 13 "trixie" from the `python:*-slim-trixie` base).
- **Python packages** installed in the image (`site-packages/*.dist-info`), e.g. Flask, Gunicorn, Werkzeug.

## Why this policy
- **HIGH/CRITICAL only:** these are the vulnerabilities most likely to be exploitable with serious
  impact. Blocking on every LOW/MEDIUM finding would stop almost every build and people would start
  ignoring the gate.
- **Only when a fix exists:** if no fixed version exists, failing the build cannot be fixed by the
  developer and would block every release (including security releases). Unfixed findings are still
  visible with a full manual scan (`trivy image splitease:build-<N>`) and are re-checked on every
  build: as soon as a fix is published, the gate starts failing until we upgrade.
- **`--exit-code 1`:** makes Trivy return an error code, which is what makes Jenkins stop the
  pipeline.

## How we keep images passing (remediation)
1. `docker build --pull` always uses the newest patched base image.
2. The Dockerfile runs `apt-get upgrade` to apply Debian security fixes published after the base
   image was built. (In our first scan, `zlib1g` had two HIGH CVEs fixed in `deb13u1` that the base
   image didn't yet include.)
3. `pip` is removed from the final image after installing dependencies. The running app doesn't need
   it, and pip bundles its own copies of `urllib3`, `msgpack` and `setuptools`, which had HIGH CVEs in
   our first scan.
4. Python dependencies are pinned in `app/requirements.txt` and upgraded deliberately when Trivy
   reports a fixed version.

## Exceptions
None at the moment. If an exception is ever unavoidable, it goes in a `.trivyignore` file with the
CVE ID, a written justification, and a review date. It must never be added silently to make a
build pass.

## Evidence (verified 2026-11-10, Trivy 0.76.1)
| Image | Result |
|---|---|
| `splitease` with `python:3.14.10-slim-trixie`, before hardening | **FAIL**: zlib1g (2 HIGH), pip-bundled urllib3/msgpack/setuptools (5 HIGH) |
| `splitease` after `apt-get upgrade` + pip removal | **PASS**: 0 HIGH/CRITICAL |
| Demo: `gunicorn==21.2.0` | **FAIL**: CVE-2024-1135, CVE-2024-6827 (HIGH, fixed in 22.0.0) |

## Trivy itself
Trivy is installed in the Jenkins image at a pinned version (0.76.1) and verified with a SHA-256
checksum. Pinning matters because Trivy's own release channel was the target of a supply-chain
attack in 2026. Upgrades are done deliberately, not automatically. The vulnerability database is
downloaded by Trivy and cached in the Jenkins home volume.
