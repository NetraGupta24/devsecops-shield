# `app/requirements.txt`

**What it does:** Lists the Python packages the app needs at runtime: **Flask** (web framework) and
**Gunicorn** (production web server).

**Why pinned versions (`==`):** Every build installs exactly the same versions, so a build that passed
yesterday behaves the same today. Pinning also means Trivy scans a known set of packages. When a
package gets a security fix, you bump the version here on purpose.

**How it connects:** The `Dockerfile` installs these into the image. The vulnerable-image demo branch
pins an old Gunicorn with a known HIGH CVE to make Trivy fail.
