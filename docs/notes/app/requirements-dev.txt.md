# `app/requirements-dev.txt`

**What it does:** Adds **pytest** on top of `requirements.txt` (`-r requirements.txt` includes it).

**Why separate:** Test tools are needed in Jenkins, but not in the production image. A smaller image
has fewer packages, so it has fewer possible vulnerabilities.

**How it connects:** The Jenkins *Unit tests* stage runs `pip install -r app/requirements-dev.txt`
inside a fresh virtual environment.
